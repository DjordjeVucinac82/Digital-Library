# Prod Deployment — Digital Library

Deploy the full stack to production from scratch. Run steps in order.

---

## 1. Prerequisites

```bash
brew install awscli terraform kubectl helm jq
aws --version        # >= 2.0
terraform -version   # >= 1.6
```

---

## 2. AWS Profile

```bash
aws configure --profile Digital-Library
# region: eu-central-1

aws sts get-caller-identity --profile Digital-Library
```

---

## 3. Bootstrap State Backend (once per account)

```bash
cd infra/bootstrap
terraform init
terraform plan -out=.tfplan
terraform apply
```

> Do not delete `infra/bootstrap/terraform.tfstate` — it tracks the S3 state bucket.

---

## 4. Deploy Prod Infrastructure

```bash
cd infra/environments/prod
terraform init
terraform plan -out=.tfplan
terraform apply      # ~15 min — EKS cluster takes longest
terraform output     # save these values, needed in later steps
```

---

## 5. Build and Push Docker Images to ECR

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile Digital-Library)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com"
IMAGE_TAG=$(git rev-parse --short HEAD)

# ECR login
aws ecr get-login-password --region eu-central-1 --profile Digital-Library \
  | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Build and push (--platform linux/amd64 targets EKS nodes; buildx --push skips a separate push step)
docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/frontend:${IMAGE_TAG}   ./frontend

docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/compressor:${IMAGE_TAG} ./compressor

docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/worker:${IMAGE_TAG}     ./worker
```

---

## 6. Configure kubectl

```bash
CLUSTER_NAME=$(terraform -chdir=infra/environments/prod output -raw cluster_name)

aws eks update-kubeconfig \
  --name ${CLUSTER_NAME} \
  --region eu-central-1 \
  --profile Digital-Library

kubectl get nodes   # expect 4 nodes in Ready state
```

---

## 7. Install AWS Load Balancer Controller

Creates ALBs in AWS when you apply a Kubernetes Ingress. Must be installed before step 12.

```bash
LB_CONTROLLER_IRSA=$(terraform -chdir=infra/environments/prod output -raw lb_controller_irsa_arn)
CLUSTER_NAME=$(terraform -chdir=infra/environments/prod output -raw cluster_name)
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} \
  --query "cluster.resourcesVpcConfig.vpcId" --output text --profile Digital-Library)

helm repo add eks https://aws.github.io/eks-charts && helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${LB_CONTROLLER_IRSA} \
  --set region=eu-central-1 \
  --set vpcId=${VPC_ID}

kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
```

---

## 8. Install external-dns

Automatically creates the Route 53 A record `444noresponse.com → ALB` when the Ingress is applied.

```bash
EXTERNAL_DNS_IRSA=$(terraform -chdir=infra/environments/prod output -raw external_dns_irsa_arn)

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ && helm repo update

helm install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set provider.name=aws \
  --set policy=sync \
  --set txtOwnerId=digital-library-prod \
  --set "domainFilters[0]=444noresponse.com" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${EXTERNAL_DNS_IRSA}

kubectl rollout status deployment/external-dns -n kube-system --timeout=120s
```

---

## 9. Install Scaling Controllers

### Metrics Server (required for HPA)

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ && helm repo update

helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set 'args[0]=--kubelet-insecure-tls'

kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
kubectl top nodes   # verify after ~60s
```

### Cluster Autoscaler

```bash
CA_IRSA=$(terraform -chdir=infra/environments/prod output -raw cluster_autoscaler_irsa_arn)
CLUSTER_NAME=$(terraform -chdir=infra/environments/prod output -raw cluster_name)

helm repo add autoscaler https://kubernetes.github.io/autoscaler && helm repo update

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=${CLUSTER_NAME} \
  --set awsRegion=eu-central-1 \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set 'rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn'=${CA_IRSA} \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set image.tag=v1.31.0

kubectl rollout status deployment/cluster-autoscaler-aws-cluster-autoscaler -n kube-system --timeout=120s
```

### KEDA (scales worker by SQS queue depth)

```bash
KEDA_IRSA=$(terraform -chdir=infra/environments/prod output -raw keda_operator_irsa_arn)

helm repo add kedacore https://kedacore.github.io/charts && helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set serviceAccount.operator.annotations."eks\.amazonaws\.com/role-arn"=${KEDA_IRSA}

kubectl rollout status deployment/keda-operator -n keda --timeout=120s
```

---

## 9.5. Install Monitoring Stack (Prometheus + Grafana)

Deploys `kube-prometheus-stack` into a dedicated `monitoring` namespace. Installs:
- **Prometheus** — scrapes metrics from all 3 application services and cluster nodes
- **Grafana** — pre-loaded Spring Boot JVM dashboard (ID 11378) + node CPU/memory dashboards
- **node-exporter** — DaemonSet providing host-level CPU, memory, disk metrics per EKS node
- **kube-state-metrics** — Deployment, Pod, HPA, PDB state metrics

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values infra/helm/monitoring/values.yaml

kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=180s
kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring --timeout=300s
```

Apply the ServiceMonitor resources (tell Prometheus which app services to scrape):

```bash
kubectl apply -f infra/k8s/monitoring/
```

Access Grafana and Prometheus locally via port-forward:

```bash
# Grafana — http://localhost:3001  (login: admin / digital-library-grafana)
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring

# Prometheus — http://localhost:9090
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

Verify all three app targets appear as UP in Prometheus at http://localhost:9090/targets
under `serviceMonitor/digital-library/compressor`, `worker`, and `frontend`.

---

## 10. Create Namespace and DB Secret

```bash
kubectl apply -f infra/k8s/namespace.yaml

# Pull DB credentials from Secrets Manager
DB_SECRET_ARN=$(terraform -chdir=infra/environments/prod output -raw db_secret_arn)
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${DB_SECRET_ARN}" \
  --query SecretString --output text --profile Digital-Library)

DB_USER=$(echo $SECRET | jq -r .username)
DB_PASS=$(echo $SECRET | jq -r .password)

kubectl create secret generic worker-db-secret \
  --from-literal=DB_USER=${DB_USER} \
  --from-literal=DB_PASS=${DB_PASS} \
  --namespace digital-library

kubectl get secret worker-db-secret -n digital-library
```

---

## 11. Render Manifest Placeholders

The script reads all values from Terraform outputs and writes filled-in manifests to
`infra/k8s-rendered/prod/` — the source files in `infra/k8s/` are never modified.

```bash
./scripts/configure-manifests-prod.sh              # image tag = current git SHA
# or pass an explicit tag:
./scripts/configure-manifests-prod.sh abc1234
```

Verify nothing was missed before applying:

```bash
grep -r "REPLACE_WITH_" infra/k8s-rendered/prod/   # must return nothing
```

---

## 12. Apply Kubernetes Manifests

```bash
# Service accounts first — IRSA must be in place before pods start
kubectl apply -f infra/k8s-rendered/prod/namespace.yaml
kubectl apply -f infra/k8s-rendered/prod/compressor/serviceaccount.yaml
kubectl apply -f infra/k8s-rendered/prod/worker/serviceaccount.yaml

# ConfigMaps
kubectl apply -f infra/k8s-rendered/prod/compressor/configmap.yaml
kubectl apply -f infra/k8s-rendered/prod/worker/configmap.yaml

# Workloads (picks up Deployment, Service, HPA, PDB, ScaledObject)
kubectl apply -f infra/k8s-rendered/prod/frontend/
kubectl apply -f infra/k8s-rendered/prod/compressor/
kubectl apply -f infra/k8s-rendered/prod/worker/

# Wait for rollouts
kubectl rollout status deployment/frontend   -n digital-library --timeout=300s
kubectl rollout status deployment/compressor -n digital-library --timeout=300s
kubectl rollout status deployment/worker     -n digital-library --timeout=300s
```

---

## 13. Verify

```bash
kubectl get pods        -n digital-library
kubectl get hpa         -n digital-library   # TARGETS should show CPU%
kubectl get scaledobject -n digital-library  # READY=True
kubectl get pdb         -n digital-library

# ALB takes ~2 min to provision
kubectl get ingress frontend -n digital-library

# Test the endpoints
curl -L https://444noresponse.com/
curl -L https://444noresponse.com/api/actuator/health

kubectl logs -l app=compressor -n digital-library --tail=50
kubectl logs -l app=worker     -n digital-library --tail=50
```

---

## 14. CI/CD Setup

### GitHub Secrets

Go to **Settings → Secrets → Actions** and add:

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | 12-digit account ID |
| `AWS_ACCESS_KEY_ID` | IAM user key with ECR push + EKS access |
| `AWS_SECRET_ACCESS_KEY` | matching secret |

### Grant CI/CD user access to the prod cluster

```bash
CI_USER_ARN=$(aws iam get-user --user-name digital-library-cicd \
  --query User.Arn --output text --profile Digital-Library)

aws eks create-access-entry \
  --cluster-name digital-library-prod \
  --principal-arn ${CI_USER_ARN} \
  --type STANDARD \
  --profile Digital-Library

aws eks associate-access-policy \
  --cluster-name digital-library-prod \
  --principal-arn ${CI_USER_ARN} \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=cluster \
  --profile Digital-Library
```

### Trigger a prod deploy

```bash
gh workflow run cd.yml -f environment=prod
```

---

## 15. Tear Down

> Delete K8s resources **before** `terraform destroy` — the ALB holds VPC ENIs and will block the destroy.

```bash
# 1. Remove workloads (this deletes the ALB)
kubectl delete -f infra/k8s/frontend/
kubectl delete -f infra/k8s/compressor/
kubectl delete -f infra/k8s/worker/
kubectl delete -f infra/k8s/namespace.yaml

sleep 60   # wait for ALB to be fully removed

# 2. Uninstall Helm releases
helm uninstall keda                          -n keda
helm uninstall kube-prometheus-stack         -n monitoring
helm uninstall external-dns                  -n kube-system
helm uninstall aws-load-balancer-controller  -n kube-system
helm uninstall cluster-autoscaler            -n kube-system
helm uninstall metrics-server                -n kube-system
kubectl delete namespace keda
kubectl delete namespace monitoring

# 3. Destroy infrastructure
cd infra/environments/prod
terraform destroy
```
