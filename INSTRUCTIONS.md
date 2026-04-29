# Deployment Instructions — Digital Library on AWS EKS

Step-by-step guide to deploy the full stack from scratch. Follow the steps in order.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [AWS Profile Setup](#2-aws-profile-setup)
3. [Bootstrap — State Backend (one-time)](#3-bootstrap--state-backend-one-time)
4. [Deploy Dev Infrastructure](#4-deploy-dev-infrastructure)
5. [Build and Push Docker Images to ECR](#5-build-and-push-docker-images-to-ecr)
6. [Configure kubectl](#6-configure-kubectl)
7. [Install AWS Load Balancer Controller](#7-install-aws-load-balancer-controller)
8. [Install external-dns](#8-install-external-dns)
9. [Install Scaling Controllers](#9-install-scaling-controllers)
10. [Create Kubernetes Namespace and Secrets](#10-create-kubernetes-namespace-and-secrets)
11. [Update K8s Manifests with Terraform Outputs](#11-update-k8s-manifests-with-terraform-outputs)
12. [Apply Kubernetes Manifests](#12-apply-kubernetes-manifests)
13. [Verify the Deployment](#13-verify-the-deployment)
14. [Deploy Prod Infrastructure](#14-deploy-prod-infrastructure)
15. [Deploy Test Infrastructure](#15-deploy-test-infrastructure)
16. [CI/CD Pipeline Setup](#16-cicd-pipeline-setup)
17. [Tear Down](#17-tear-down)

---

## 1. Prerequisites

Install the following tools before starting:

```bash
# AWS CLI v2
brew install awscli
aws --version   # should be >= 2.0

# Terraform
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
terraform -version   # should be >= 1.6

# kubectl
brew install kubectl
kubectl version --client

# Helm (for the AWS Load Balancer Controller)
brew install helm
helm version

# jq (for parsing JSON from AWS CLI)
brew install jq
```

---

## 2. AWS Profile Setup

The project uses the `Digital-Library` AWS profile for local Terraform and kubectl access.

```bash
# Add credentials to ~/.aws/credentials
aws configure --profile Digital-Library
# Enter your AWS Access Key ID, Secret Access Key, and region: eu-central-1

# Verify access
aws sts get-caller-identity --profile Digital-Library
```

---

## 3. Bootstrap — State Backend (one-time)

Run this once per AWS account to create the S3 bucket and DynamoDB table that store Terraform state.

```bash
cd infra/bootstrap

terraform init
terraform apply

# Confirm the plan and type 'yes'
# Expected output: state bucket + lock table created
```

> **Note:** The bootstrap itself uses local Terraform state (`infra/bootstrap/terraform.tfstate`). Do not delete this file — it tracks the S3 bucket.

---

## 4. Deploy Dev Infrastructure

```bash
cd infra/environments/dev

# Download providers and configure the S3 backend
terraform init

# Preview what will be created (~30 resources)
terraform plan

# Apply — takes ~15 minutes (EKS cluster takes longest)
terraform apply

# Save the outputs — you will need them in later steps
terraform output
```

Key outputs to note:

| Output | Used in |
|---|---|
| `cluster_name` | kubectl config, CD pipeline |
| `ecr_repository_urls` | K8s manifests, docker push |
| `sqs_queue_url` | K8s ConfigMap |
| `db_endpoint` | K8s ConfigMap |
| `db_secret_arn` | Step 9 |
| `compressor_irsa_arn` | K8s ServiceAccount |
| `worker_irsa_arn` | K8s ServiceAccount |
| `lb_controller_irsa_arn` | Helm values (step 7) |
| `external_dns_irsa_arn` | Helm values (step 8) |
| `cluster_autoscaler_irsa_arn` | Helm values (step 9) |
| `keda_operator_irsa_arn` | Helm values (step 9) |
| `certificate_arn` | K8s Ingress annotation (step 11) |
| `s3_bucket_name` | K8s ConfigMap (step 11) |

---

## 5. Build and Push Docker Images to ECR

ECR repositories must exist (created in Step 4) before you can push images.
Images must be in ECR before the first `kubectl apply` (pods pull from ECR on startup).

```bash
# Get your account ID and the ECR registry base URL
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile Digital-Library)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com"

# Log in to ECR
aws ecr get-login-password --region eu-central-1 --profile Digital-Library \
  | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Build for linux/amd64 (EKS nodes are x86_64 — Mac M-series would produce arm64 images otherwise)
# --push streams each layer directly to ECR without a local intermediate copy
docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/frontend:latest ./frontend

docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/compressor:latest ./compressor

docker buildx build --platform linux/amd64 --push \
  -t ${ECR_REGISTRY}/digital-library/worker:latest ./worker

echo "Registry: ${ECR_REGISTRY}"
```

> **Note:** All K8s Deployments have `imagePullPolicy: Always` so `kubectl rollout restart` will always pull the latest image regardless of the `:latest` tag being unchanged.

---

## 6. Configure kubectl

```bash
# Get the cluster name from Terraform output
CLUSTER_NAME=$(terraform -chdir=infra/environments/dev output -raw cluster_name)

# Add the cluster to your kubeconfig
aws eks update-kubeconfig \
  --name ${CLUSTER_NAME} \
  --region eu-central-1 \
  --profile Digital-Library

# Verify you can reach the cluster
kubectl get nodes
# Expected: 4 nodes in Ready state (2 frontend, 2 backend)
```

---

## 7. Install AWS Load Balancer Controller

The AWS Load Balancer Controller watches Kubernetes Ingress objects and creates ALBs in AWS.
It must be installed before applying any Ingress manifest.

```bash
# Get the LB Controller IAM role ARN from Terraform output
LB_CONTROLLER_IRSA=$(terraform -chdir=infra/environments/dev output -raw lb_controller_irsa_arn)
CLUSTER_NAME=$(terraform -chdir=infra/environments/dev output -raw cluster_name)

# Add the EKS chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller in kube-system namespace
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${LB_CONTROLLER_IRSA} \
  --set region=eu-central-1 \
  --set vpcId=$(terraform -chdir=infra/environments/dev output -raw cluster_name | xargs -I {} aws eks describe-cluster --name {} --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Wait for the controller to be ready
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
```

---

## 8. Install external-dns

external-dns watches Kubernetes Ingress objects and automatically creates Route 53 A ALIAS records
pointing your domain (`dev.444noresponse.com` / `444noresponse.com`) to the ALB.
It must be installed before applying the Ingress manifest.

```bash
# Get the external-dns IAM role ARN from Terraform output
EXTERNAL_DNS_IRSA=$(terraform -chdir=infra/environments/dev output -raw external_dns_irsa_arn)

# Add the external-dns Helm repository
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

# Install external-dns in kube-system
# - provider=aws  : use Route 53 as the DNS backend
# - policy=sync   : create AND delete records (keeps DNS in sync with K8s state)
# - txtOwnerId    : unique identifier written into TXT records so external-dns
#                   only manages records it created (prevents stepping on other tools)
# - domainFilters : restrict external-dns to only manage records under this zone
helm install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set provider.name=aws \
  --set policy=sync \
  --set txtOwnerId=digital-library-dev \
  --set "domainFilters[0]=444noresponse.com" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${EXTERNAL_DNS_IRSA}

# Verify the controller is running
kubectl rollout status deployment/external-dns -n kube-system --timeout=120s

# Confirm it authenticated to Route 53 successfully (look for "Applying provider record changes")
kubectl logs -l app.kubernetes.io/name=external-dns -n kube-system --tail=20
```

> **How the DNS flow works:**
> 1. You apply the Ingress manifest — the ALB Controller creates the ALB and populates `status.loadBalancer.ingress[0].hostname`
> 2. external-dns detects the `external-dns.alpha.kubernetes.io/hostname` annotation and reads the ALB hostname
> 3. external-dns creates a Route 53 A ALIAS record: `dev.444noresponse.com` → ALB DNS name
> 4. When the Ingress is deleted, external-dns removes the record automatically (`policy=sync`)

---

## 9. Install Scaling Controllers

Install three components that enable dynamic scaling: Metrics Server (prerequisite for HPA),
Cluster Autoscaler (node-level scaling), and KEDA (queue-depth-based worker scaling).

**Must run after `terraform apply`** — the IRSA roles and ASG discovery tags must exist first.

```bash
# Collect IRSA ARNs and cluster name from Terraform
CA_IRSA=$(terraform -chdir=infra/environments/dev output -raw cluster_autoscaler_irsa_arn)
KEDA_IRSA=$(terraform -chdir=infra/environments/dev output -raw keda_operator_irsa_arn)
CLUSTER_NAME=$(terraform -chdir=infra/environments/dev output -raw cluster_name)
```

### Metrics Server

Metrics Server exposes CPU and memory usage via the Kubernetes Metrics API. Required by HPA —
without it, `kubectl top` returns no data and HPAs report `unable to fetch metrics`.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# --kubelet-insecure-tls: EKS nodes use self-signed kubelet certificates.
# Without this flag, Metrics Server cannot scrape node metrics.
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls"

kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s

# Verify it's collecting data (wait ~60s for the first scrape)
kubectl top nodes
```

### Cluster Autoscaler

Cluster Autoscaler watches for `Pending` pods (no schedulable node) and scales up the appropriate
node group. It also scales down underutilised nodes, respecting PodDisruptionBudgets.

The EKS node groups are tagged for auto-discovery (set in Terraform):
`k8s.io/cluster-autoscaler/enabled=true` and `k8s.io/cluster-autoscaler/<cluster-name>=owned`.

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=${CLUSTER_NAME} \
  --set awsRegion=eu-central-1 \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${CA_IRSA} \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false

kubectl rollout status deployment/cluster-autoscaler -n kube-system --timeout=120s
```

> `balance-similar-node-groups=true` distributes nodes evenly across AZs.
> `skip-nodes-with-system-pods=false` allows scale-in on nodes that only run
> DaemonSet pods (kube-proxy, vpc-cni) — otherwise the cluster never shrinks.

### KEDA

KEDA (Kubernetes Event-Driven Autoscaler) scales the worker Deployment based on the depth of
the SQS queue. The operator pod uses its own IRSA identity to call `sqs:GetQueueAttributes`
every 30 seconds. No TriggerAuthentication resource is needed.

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set serviceAccount.operator.annotations."eks\.amazonaws\.com/role-arn"=${KEDA_IRSA}

kubectl rollout status deployment/keda-operator -n keda --timeout=120s
```

> KEDA is installed in its own `keda` namespace (chart default). The IRSA annotation on the
> `keda-operator` ServiceAccount allows the operator to read SQS queue depth.
> The worker ScaledObject (`infra/k8s/worker/scaledobject.yaml`) uses `identityOwner: operator`
> which tells KEDA to use this operator role — no per-ScaledObject credentials needed.

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

> **How scraping works:** `serviceMonitorSelectorNilUsesHelmValues: false` in `values.yaml`
> tells Prometheus to discover ServiceMonitors in all namespaces. The three ServiceMonitor
> resources in `infra/k8s/monitoring/` point Prometheus at the correct service ports and paths.

---

## 10. Create Kubernetes Namespace and Secrets

### Create namespace

```bash
kubectl apply -f infra/k8s/namespace.yaml
```

### Pull DB credentials from Secrets Manager and create K8s Secret

The RDS password was generated by Terraform and stored in AWS Secrets Manager.
Pull it and create a Kubernetes Secret in the cluster:

```bash
# Get the secret ARN from Terraform output
DB_SECRET_ARN=$(terraform -chdir=infra/environments/dev output -raw db_secret_arn)

# Pull the full JSON secret from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${DB_SECRET_ARN}" \
  --query SecretString \
  --output text \
  --profile Digital-Library)

# Extract individual fields
DB_USER=$(echo $SECRET | jq -r .username)
DB_PASS=$(echo $SECRET | jq -r .password)

# Create the K8s Secret in the digital-library namespace
kubectl create secret generic worker-db-secret \
  --from-literal=DB_USER=${DB_USER} \
  --from-literal=DB_PASS=${DB_PASS} \
  --namespace digital-library

# Verify the secret was created (values are base64-encoded, not shown in plaintext)
kubectl get secret worker-db-secret -n digital-library
```

> **Production best practice:** Use the [External Secrets Operator](https://external-secrets.io/) to automatically sync Secrets Manager secrets into Kubernetes Secrets. This handles rotation without manual re-runs.

---

## 11. Update K8s Manifests with Terraform Outputs

The K8s manifests contain `REPLACE_WITH_*` placeholders that must be filled in before applying.

### Option A — automated script (recommended for prod)

```bash
# Renders infra/k8s/ → infra/k8s-rendered/prod/ with all placeholders substituted.
# Reads all values directly from terraform output — no manual variable setting needed.
./scripts/configure-manifests-prod.sh
```

The script substitutes: ECR registry, SQS queue URL, DB host, S3 bucket name, IRSA ARNs,
ACM certificate ARN, and app domain. The rendered output is git-ignored; re-run the script
whenever Terraform outputs change.

### Option B — manual substitution

```bash
# Collect all the values you need
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com"
SQS_QUEUE_URL=$(terraform -chdir=infra/environments/dev output -raw sqs_queue_url)
DB_HOST=$(terraform -chdir=infra/environments/dev output -raw db_endpoint)
S3_BUCKET=$(terraform -chdir=infra/environments/dev output -raw s3_bucket_name)
COMPRESSOR_IRSA=$(terraform -chdir=infra/environments/dev output -raw compressor_irsa_arn)
WORKER_IRSA=$(terraform -chdir=infra/environments/dev output -raw worker_irsa_arn)
CERT_ARN=$(terraform -chdir=infra/environments/dev output -raw certificate_arn)
APP_DOMAIN="dev.444noresponse.com"   # use 444noresponse.com for prod

# Frontend deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/frontend:latest|${ECR_REGISTRY}/digital-library/frontend:latest|g" \
  infra/k8s/frontend/deployment.yaml

# Compressor deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/compressor:latest|${ECR_REGISTRY}/digital-library/compressor:latest|g" \
  infra/k8s/compressor/deployment.yaml

# Worker deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/worker:latest|${ECR_REGISTRY}/digital-library/worker:latest|g" \
  infra/k8s/worker/deployment.yaml

# Compressor configmap — SQS URL + S3 bucket
sed -i '' "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_QUEUE_URL}|g" \
  infra/k8s/compressor/configmap.yaml
sed -i '' "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g" \
  infra/k8s/compressor/configmap.yaml

# Worker configmap — SQS URL, DB host, S3 bucket
sed -i '' "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_QUEUE_URL}|g" \
  infra/k8s/worker/configmap.yaml
sed -i '' "s|REPLACE_WITH_DB_HOST|${DB_HOST}|g" \
  infra/k8s/worker/configmap.yaml
sed -i '' "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g" \
  infra/k8s/worker/configmap.yaml

# ServiceAccounts — IRSA ARNs
sed -i '' "s|REPLACE_WITH_COMPRESSOR_IRSA_ARN|${COMPRESSOR_IRSA}|g" \
  infra/k8s/compressor/serviceaccount.yaml
sed -i '' "s|REPLACE_WITH_WORKER_IRSA_ARN|${WORKER_IRSA}|g" \
  infra/k8s/worker/serviceaccount.yaml

# Ingress — ACM certificate ARN and domain name
sed -i '' "s|REPLACE_WITH_CERT_ARN|${CERT_ARN}|g" \
  infra/k8s/frontend/ingress.yaml
sed -i '' "s|REPLACE_WITH_APP_DOMAIN|${APP_DOMAIN}|g" \
  infra/k8s/frontend/ingress.yaml

# Worker ScaledObject — SQS URL for the KEDA queue-depth trigger
sed -i '' "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_QUEUE_URL}|g" \
  infra/k8s/worker/scaledobject.yaml
```

---

## 12. Apply Kubernetes Manifests

Apply in the correct order: namespace → service accounts → config → workloads → networking.
The glob `kubectl apply -f infra/k8s/<service>/` picks up all YAML files in the directory,
including the new hpa.yaml, pdb.yaml, and scaledobject.yaml files automatically.

**KEDA must be running (step 9) before applying** — the ScaledObject CRD won't exist otherwise.

```bash
# Namespace (must exist before all other resources)
kubectl apply -f infra/k8s/namespace.yaml

# Service accounts (needed before Deployments for IRSA to work)
kubectl apply -f infra/k8s/compressor/serviceaccount.yaml
kubectl apply -f infra/k8s/worker/serviceaccount.yaml

# ConfigMaps
kubectl apply -f infra/k8s/compressor/configmap.yaml
kubectl apply -f infra/k8s/worker/configmap.yaml

# Deployments, Services, HPA, PDB, ScaledObject (all picked up by directory glob)
kubectl apply -f infra/k8s/frontend/
kubectl apply -f infra/k8s/compressor/
kubectl apply -f infra/k8s/worker/

# Wait for all pods to be ready
kubectl rollout status deployment/frontend -n digital-library --timeout=300s
kubectl rollout status deployment/compressor -n digital-library --timeout=300s
kubectl rollout status deployment/worker -n digital-library --timeout=300s
```

---

## 13. Verify the Deployment

```bash
# Check all pods are Running
kubectl get pods -n digital-library

# Verify scaling resources are active
kubectl get hpa -n digital-library          # frontend + compressor (TARGETS should show CPU%)
kubectl get scaledobject -n digital-library  # worker (READY=True)
kubectl get pdb -n digital-library          # all 3 services

# Get the ALB URL (takes ~2 minutes for the ALB to provision)
kubectl get ingress frontend -n digital-library

# Confirm external-dns created the Route 53 record
kubectl logs -l app.kubernetes.io/name=external-dns -n kube-system --tail=10

# Test via the custom domain (HTTP redirects to HTTPS automatically)
curl -L https://dev.444noresponse.com/
curl -L https://dev.444noresponse.com/api/actuator/health

# Check compressor and worker logs
kubectl logs -l app=compressor -n digital-library --tail=50
kubectl logs -l app=worker -n digital-library --tail=50
```

---

## 14. Deploy Prod Infrastructure

Repeat Steps 4–13 for prod, substituting `dev` with `prod`:

```bash
# Deploy infrastructure
cd infra/environments/prod
terraform init
terraform apply

# Configure kubectl for prod cluster
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region eu-central-1

# Repeat Steps 5–13 with prod outputs
# For step 8 (external-dns), use txtOwnerId=digital-library-prod
# For step 9 (scaling controllers), substitute prod IRSA ARNs
# For step 11 (manifests), set APP_DOMAIN=444noresponse.com
```

Key differences in prod:
- Domain: `444noresponse.com` (no `dev.` prefix)
- RDS is Multi-AZ (automatic failover)
- Two NAT gateways (one per AZ for HA)
- On-demand EC2 instances (no Spot interruptions)
- DB secret ARN is `digital-library/prod/db-password`

---

## 15. Deploy Test Infrastructure

The test environment mirrors dev (spot instances, single NAT GW, `db.t3.micro`).
Use it to validate infrastructure or application changes before promoting to prod.

Repeat Steps 4–13, substituting `dev` → `test`:

```bash
# Deploy infrastructure
cd infra/environments/test
terraform init
terraform apply

# Configure kubectl for the test cluster
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region eu-central-1 --profile Digital-Library

# Repeat Steps 5–13 with test outputs
# For step 8 (external-dns), use txtOwnerId=digital-library-test
# For step 11 (manifests), set APP_DOMAIN=test.444noresponse.com
```

Key differences vs dev:

| Setting | Dev | Test |
|---|---|---|
| VPC CIDR | `10.0.0.0/16` | `10.2.0.0/16` |
| EKS cluster | `digital-library-dev` | `digital-library-test` |
| Domain | `dev.444noresponse.com` | `test.444noresponse.com` |
| external-dns txtOwnerId | `digital-library-dev` | `digital-library-test` |
| TF state key | `dev/terraform.tfstate` | `test/terraform.tfstate` |

---

## 16. CI/CD Pipeline Setup


### GitHub Secrets required

Go to GitHub → Settings → Secrets and variables → Actions → New repository secret:

| Secret name | Value |
|---|---|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM user access key with ECR push + EKS access |
| `AWS_SECRET_ACCESS_KEY` | Matching secret key |

### IAM permissions for the CI/CD user

The IAM user (`AWS_ACCESS_KEY_ID`) needs the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["eks:DescribeCluster"],
      "Resource": "arn:aws:eks:eu-central-1:*:cluster/digital-library-*"
    }
  ]
}
```

### Allow the CI/CD IAM user to access the cluster

After creating each cluster, run this to allow the CI/CD IAM user to call `kubectl`:

```bash
# Get the CI/CD IAM user ARN
CI_USER_ARN=$(aws iam get-user --user-name digital-library-cicd --query User.Arn --output text)

# Create an EKS access entry for the CI/CD user
aws eks create-access-entry \
  --cluster-name digital-library-dev \
  --principal-arn ${CI_USER_ARN} \
  --type STANDARD

# Grant the CI/CD user admin access to the cluster
aws eks associate-access-policy \
  --cluster-name digital-library-dev \
  --principal-arn ${CI_USER_ARN} \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=cluster
```

### Trigger a deployment

```bash
# Manual deploy to dev
gh workflow run cd.yml -f environment=dev

# Manual deploy to prod
gh workflow run cd.yml -f environment=prod

# Automatic deploy — push to main branch triggers dev deploy
git push origin main
```

---

## 17. Tear Down

> **Important:** Delete Kubernetes resources BEFORE running `terraform destroy`.
> If the Ingress is still present when Terraform destroys the VPC, the ALB holds
> ENIs (elastic network interfaces) in the VPC subnets, and Terraform cannot delete them.

```bash
# Step 1: Delete all K8s resources (this removes the ALB)
kubectl delete -f infra/k8s/frontend/
kubectl delete -f infra/k8s/compressor/
kubectl delete -f infra/k8s/worker/
kubectl delete -f infra/k8s/namespace.yaml

# Wait for the ALB to be fully deleted (~60 seconds)
sleep 60

# Step 2: Uninstall Helm releases
# Order matters: KEDA first (stops ScaledObject reconciliation), then monitoring,
# then external-dns (stops Route 53 updates), then LB controller, then metrics/autoscaler
helm uninstall keda                          -n keda
helm uninstall kube-prometheus-stack         -n monitoring
helm uninstall external-dns                  -n kube-system
helm uninstall aws-load-balancer-controller  -n kube-system
helm uninstall cluster-autoscaler            -n kube-system
helm uninstall metrics-server                -n kube-system

# Remove namespaces (charts do not delete them automatically)
kubectl delete namespace keda
kubectl delete namespace monitoring

# Step 3: Destroy the Terraform infrastructure
cd infra/environments/dev
terraform destroy

# For test:
cd infra/environments/test
terraform destroy

# For prod:
cd infra/environments/prod
terraform destroy

# Step 4: Destroy the bootstrap (only if you want to completely clean up)
# WARNING: This deletes the Terraform state bucket — only do this if you're sure.
# cd infra/bootstrap && terraform destroy
```
