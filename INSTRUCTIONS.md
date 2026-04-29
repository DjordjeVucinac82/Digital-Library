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
9. [Create Kubernetes Namespace and Secrets](#9-create-kubernetes-namespace-and-secrets)
10. [Update K8s Manifests with Terraform Outputs](#10-update-k8s-manifests-with-terraform-outputs)
11. [Apply Kubernetes Manifests](#11-apply-kubernetes-manifests)
12. [Verify the Deployment](#12-verify-the-deployment)
13. [Deploy Prod Infrastructure](#13-deploy-prod-infrastructure)
14. [CI/CD Pipeline Setup](#14-cicd-pipeline-setup)
15. [Tear Down](#15-tear-down)

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
| `certificate_arn` | K8s Ingress annotation (step 10) |

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

# Build and push all three images
IMAGE_TAG=$(git rev-parse --short HEAD)

docker build -t ${ECR_REGISTRY}/digital-library/frontend:${IMAGE_TAG} ./frontend
docker build -t ${ECR_REGISTRY}/digital-library/compressor:${IMAGE_TAG} ./compressor
docker build -t ${ECR_REGISTRY}/digital-library/worker:${IMAGE_TAG} ./worker

docker push ${ECR_REGISTRY}/digital-library/frontend:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/digital-library/compressor:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/digital-library/worker:${IMAGE_TAG}

echo "Image tag: ${IMAGE_TAG}"
echo "Registry:  ${ECR_REGISTRY}"
```

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

## 9. Create Kubernetes Namespace and Secrets

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

## 10. Update K8s Manifests with Terraform Outputs

The K8s manifests contain `REPLACE_WITH_*` placeholders that must be filled in before applying.

```bash
# Collect all the values you need
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.eu-central-1.amazonaws.com"
IMAGE_TAG=$(git rev-parse --short HEAD)
SQS_QUEUE_URL=$(terraform -chdir=infra/environments/dev output -raw sqs_queue_url)
DB_HOST=$(terraform -chdir=infra/environments/dev output -raw db_endpoint)
COMPRESSOR_IRSA=$(terraform -chdir=infra/environments/dev output -raw compressor_irsa_arn)
WORKER_IRSA=$(terraform -chdir=infra/environments/dev output -raw worker_irsa_arn)
CERT_ARN=$(terraform -chdir=infra/environments/dev output -raw certificate_arn)
APP_DOMAIN="dev.444noresponse.com"   # use 444noresponse.com for prod

# Frontend deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/frontend:latest|${ECR_REGISTRY}/digital-library/frontend:${IMAGE_TAG}|g" \
  infra/k8s/frontend/deployment.yaml

# Compressor deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/compressor:latest|${ECR_REGISTRY}/digital-library/compressor:${IMAGE_TAG}|g" \
  infra/k8s/compressor/deployment.yaml

# Worker deployment — update ECR image
sed -i '' "s|REPLACE_WITH_ECR_URI/digital-library/worker:latest|${ECR_REGISTRY}/digital-library/worker:${IMAGE_TAG}|g" \
  infra/k8s/worker/deployment.yaml

# Compressor configmap — SQS URL
sed -i '' "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_QUEUE_URL}|g" \
  infra/k8s/compressor/configmap.yaml

# Worker configmap — SQS URL and DB host
sed -i '' "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_QUEUE_URL}|g" \
  infra/k8s/worker/configmap.yaml
sed -i '' "s|REPLACE_WITH_DB_HOST|${DB_HOST}|g" \
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
```

---

## 11. Apply Kubernetes Manifests

Apply in the correct order: namespace → service accounts → config → workloads → networking.

```bash
# Namespace (must exist before all other resources)
kubectl apply -f infra/k8s/namespace.yaml

# Service accounts (needed before Deployments for IRSA to work)
kubectl apply -f infra/k8s/compressor/serviceaccount.yaml
kubectl apply -f infra/k8s/worker/serviceaccount.yaml

# ConfigMaps
kubectl apply -f infra/k8s/compressor/configmap.yaml
kubectl apply -f infra/k8s/worker/configmap.yaml

# Deployments and Services
kubectl apply -f infra/k8s/frontend/
kubectl apply -f infra/k8s/compressor/
kubectl apply -f infra/k8s/worker/

# Wait for all pods to be ready
kubectl rollout status deployment/frontend -n digital-library --timeout=300s
kubectl rollout status deployment/compressor -n digital-library --timeout=300s
kubectl rollout status deployment/worker -n digital-library --timeout=300s
```

---

## 12. Verify the Deployment

```bash
# Check all pods are Running (2/2 for each deployment)
kubectl get pods -n digital-library

# Get the ALB URL (takes ~2 minutes for the ALB to provision)
kubectl get ingress frontend -n digital-library

# Confirm external-dns created the Route 53 record (may take ~30 seconds after ALB is up)
kubectl logs -l app.kubernetes.io/name=external-dns -n kube-system --tail=10

# Test via the custom domain (HTTP redirects to HTTPS automatically)
curl -L https://dev.444noresponse.com/
curl -L https://dev.444noresponse.com/api/actuator/health

# Check compressor and worker logs
kubectl logs -l app=compressor -n digital-library --tail=50
kubectl logs -l app=worker -n digital-library --tail=50
```

---

## 13. Deploy Prod Infrastructure

Repeat Steps 4–12 for prod, substituting `dev` with `prod`:

```bash
# Deploy infrastructure
cd infra/environments/prod
terraform init
terraform apply

# Configure kubectl for prod cluster
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region eu-central-1

# Repeat Steps 5–12 with prod outputs
# For step 8 (external-dns), use txtOwnerId=digital-library-prod
# For step 10 (manifests), set APP_DOMAIN=444noresponse.com
```

Key differences in prod:
- Domain: `444noresponse.com` (no `dev.` prefix)
- RDS is Multi-AZ (automatic failover)
- Two NAT gateways (one per AZ for HA)
- On-demand EC2 instances (no Spot interruptions)
- DB secret ARN is `digital-library/prod/db-password`

---

## 14. CI/CD Pipeline Setup


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

## 15. Tear Down

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

# Step 2: Uninstall Helm releases (external-dns first so it stops watching for DNS changes)
helm uninstall external-dns -n kube-system
helm uninstall aws-load-balancer-controller -n kube-system

# Step 3: Destroy the Terraform infrastructure (order matters: dev first, then prod)
cd infra/environments/dev
terraform destroy

# For prod:
cd infra/environments/prod
terraform destroy

# Step 4: Destroy the bootstrap (only if you want to completely clean up)
# WARNING: This deletes the Terraform state bucket — only do this if you're sure.
# cd infra/bootstrap && terraform destroy
```
