# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This workspace is for preparing a final technical interview at Zühlke (DevOps/Cloud Engineer role). The deliverable is a 60-minute presentation: 25 min presentation + 35 min Q&A with a technical Zühlke dev team and clients.

## The Case Study

**Digital Library** — migrate an existing on-premise 3-tier application to AWS with minimal cost and maintenance effort, then optimize for cloud-native benefits.

### Application flow

```
Employees → Library Portal (React) → Compressor (Java) → S3 + SQS → Worker (Java) → RDS MySQL
```

- **Library Portal** (`frontend/`): React/Vite app — employees upload PDF books, served via nginx (port 80)
- **Compressor** (`compressor/`): Spring Boot on port 8081 — receives PDFs via REST, GZIP-compresses them, uploads compressed bytes to S3, sends the S3 key to SQS. nginx reverse-proxies `/api/*` to compressor from the frontend pod.
- **Worker** (`worker/`): Spring Boot on port 8082 — receives S3 key from SQS, downloads compressed bytes from S3, persists to RDS MySQL, deletes the S3 object
- **Message Broker**: RabbitMQ locally (`local` Spring profile) → Amazon SQS in AWS (`aws` Spring profile)
- **Database**: PostgreSQL locally → Amazon RDS MySQL in AWS

### Spring profiles

| Profile | Broker | Database | When active |
|---|---|---|---|
| `aws` (default) | SQS | RDS MySQL | EKS deployment |
| `local` | RabbitMQ | PostgreSQL | docker-compose |

### Non-functional requirements (from the brief)

- **Infrastructure as Code** — all resources managed via Terraform
- **Observability** — every service boundary emits logs/metrics via Spring Actuator (`/actuator/prometheus`); Prometheus + Grafana scrape all three services and cluster nodes
- **Scalability** — cost-effective, scales up/down; 2 replicas per service in K8s
- **Quality assurance** — unit tests for all business logic

## Repository Structure

```
Zuhlke-library/
├── frontend/                   # React/Vite — Library Portal (nginx reverse proxy)
├── compressor/                 # Java/Spring Boot — PDF compressor
│   └── src/main/resources/
│       ├── application.yml          # base config + profile selector
│       ├── application-aws.yml      # SQS config (EKS)
│       └── application-local.yml    # RabbitMQ config (docker-compose)
├── worker/                     # Java/Spring Boot — DB writer
│   └── src/main/resources/
│       ├── application.yml
│       ├── application-aws.yml      # SQS + MySQL config (EKS)
│       └── application-local.yml    # RabbitMQ + PostgreSQL config (docker-compose)
├── infra/
│   ├── bootstrap/              # S3 + DynamoDB for TF state (apply once)
│   ├── modules/
│   │   ├── vpc/                # VPC, subnets, IGW, NAT GW, route tables
│   │   ├── eks/                # EKS cluster, 2 node groups, OIDC provider
│   │   ├── ecr/                # ECR repositories (frontend, compressor, worker)
│   │   ├── iam/                # IRSA roles + node role + LB controller role
│   │   ├── rds/                # RDS MySQL + Secrets Manager password
│   │   ├── s3/                 # Transient S3 bucket for compressed PDFs (SQS size workaround)
│   │   └── sqs/                # SQS queue + DLQ
│   ├── environments/
│   │   ├── dev/                # dev tfvars + provider.tf (S3 backend)
│   │   └── prod/               # prod tfvars + provider.tf (S3 backend)
│   ├── helm/
│   │   └── monitoring/         # kube-prometheus-stack Helm values
│   └── k8s/                    # Kubernetes manifests
│       ├── namespace.yaml
│       ├── monitoring/         # ServiceMonitor resources (Prometheus scrape targets)
│       ├── frontend/           # Deployment, Service, Ingress (ALB)
│       ├── compressor/         # ServiceAccount (IRSA), ConfigMap, Deployment, Service
│       └── worker/             # ServiceAccount (IRSA), ConfigMap, Deployment, Service
├── .github/workflows/
│   ├── ci.yml                  # build + test all three services on every push
│   └── cd.yml                  # build Docker images, push to ECR, deploy to EKS
├── INSTRUCTIONS.md             # full deployment guide (bootstrap → running in prod)
└── docker-compose.yml          # full local stack (RabbitMQ + PostgreSQL + all services)
```

## Commands

### Local development (all services together)
```bash
docker-compose up --build          # start full stack (local Spring profile, RabbitMQ + PostgreSQL)
docker-compose down -v             # stop and remove volumes
```

RabbitMQ management UI: http://localhost:15672 (guest/guest)
Frontend: http://localhost:3000
Compressor API: http://localhost:8081/actuator/health
Worker API: http://localhost:8082/actuator/health

### Compressor microservice
```bash
cd compressor
mvn verify                              # build + run tests
mvn spring-boot:run                     # run locally (needs RabbitMQ on localhost:5672)
mvn test -Dtest=CompressorServiceTest   # run single test class
```

### Worker microservice
```bash
cd worker
mvn verify
mvn spring-boot:run                     # needs RabbitMQ + PostgreSQL (local profile)
mvn test -Dtest=BookStorageServiceTest
```

### Frontend
```bash
cd frontend
npm install
npm run dev                        # Vite dev server on http://localhost:5173
npm run build                      # production build to dist/
```

### Terraform (see INSTRUCTIONS.md for full sequence)
```bash
# Bootstrap — run once
cd infra/bootstrap && terraform init && terraform apply

# Dev environment
cd infra/environments/dev
terraform init && terraform plan && terraform apply
terraform output                   # get ECR URLs, SQS URL, DB host, IRSA ARNs

# Prod environment
cd infra/environments/prod
terraform init && terraform plan && terraform apply
```

### Kubernetes
```bash
# Configure kubectl
aws eks update-kubeconfig --name digital-library-dev --region eu-central-1 --profile Digital-Library

# Apply manifests (see INSTRUCTIONS.md step 11 for filling in REPLACE_WITH_* placeholders)
kubectl apply -f infra/k8s/namespace.yaml
kubectl apply -f infra/k8s/compressor/serviceaccount.yaml
kubectl apply -f infra/k8s/worker/serviceaccount.yaml
kubectl apply -f infra/k8s/

# Check pod status
kubectl get pods -n digital-library

# Get ALB URL
kubectl get ingress frontend -n digital-library
```

### Monitoring (Prometheus + Grafana)
```bash
# Install kube-prometheus-stack (see prod-steps.md step 9.5 for full sequence)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values infra/helm/monitoring/values.yaml

# Apply ServiceMonitor resources
kubectl apply -f infra/k8s/monitoring/

# Access Grafana — http://localhost:3001  (admin / digital-library-grafana)
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring

# Access Prometheus — http://localhost:9090
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

## Architecture Decisions

**Why EKS over ECS Fargate**: EKS gives fine-grained pod placement (frontend in public subnets, backend in private), native Kubernetes ecosystem (Helm, Ingress, IRSA), and is better for interview demonstration of Kubernetes skills. ECS Fargate has lower operational overhead and scales to zero — preferred for a genuine startup; EKS makes sense here for the demo and learning goals.

**Three environments (dev + test + prod)**: dev and test both use spot instances and a single NAT gateway (~$72/month per EKS control plane). Prod uses on-demand instances and Multi-AZ for HA. VPC CIDRs are non-overlapping: dev `10.0.0.0/16`, prod `10.1.0.0/16`, test `10.2.0.0/16`.

**Spring profiles for broker/DB selection**: `aws` profile (default) activates SQS + MySQL; `local` profile activates RabbitMQ + PostgreSQL. docker-compose sets `SPRING_PROFILES_ACTIVE=local`. No code changes needed between environments — only configuration.

**MessagePublisher interface** (compressor): isolates the broker from business logic. `SqsMessagePublisher` (@Profile=aws) and `RabbitMessagePublisher` (@Profile=local) implement the interface. Tests mock the interface, not the broker client.

**nginx reverse proxy** (frontend): nginx serves the React SPA and proxies `/api/*` to the compressor ClusterIP service. This means only one ALB is needed (port 80 → frontend), and the compressor is never directly exposed to the internet.

**Pod and node autoscaling**: frontend + compressor use CPU-based HPA (autoscaling/v2, 70% target, min=2/max=4). Worker uses KEDA with the AWS SQS scaler — queue depth is the correct signal for a queue-driven service, CPU is not. KEDA operator holds an IRSA role with `sqs:GetQueueAttributes`; `identityOwner: operator` in the ScaledObject avoids needing a TriggerAuthentication resource. Cluster Autoscaler handles node-level scaling via ASG discovery tags on both node groups. The `desired_size` field uses `lifecycle { ignore_changes }` so Terraform doesn't fight the autoscaler on subsequent applies. PodDisruptionBudgets (minAvailable=1) on all three services prevent simultaneous pod eviction during scale-in or node drains.

**Custom domains via external-dns**: `444noresponse.com` (prod), `dev.444noresponse.com` (dev), and `test.444noresponse.com` (test) point to their respective ALBs via Route 53. external-dns runs in `kube-system`, watches the Ingress `external-dns.alpha.kubernetes.io/hostname` annotation, and automatically creates/removes Route 53 A ALIAS records. ACM certificates are provisioned by Terraform (DNS-validated against the same hosted zone `Z0414591K81BU1BVJ424`). The ALB is configured to redirect HTTP → HTTPS.

**S3 intermediate storage for SQS size limit**: SQS has a 256 KB message limit — too small for any real PDF. Compressor uploads the compressed bytes to S3 (`digital-library-books-{env}-{account_id}`) under the `books/` prefix using a UUID key, then sends only that key to SQS. Worker downloads the bytes, persists to RDS, then deletes the S3 object. A 1-day lifecycle expiry on the bucket acts as a safety net if the worker fails to delete. Bucket name is injected via `S3_BUCKET_NAME` in the K8s ConfigMap.

**IRSA (IAM Roles for Service Accounts)**: each pod has only the permissions it needs. Compressor → SQS send + S3 PutObject on `books/*`. Worker → SQS receive + S3 GetObject + S3 DeleteObject on `books/*` + Secrets Manager read. Credentials are short-lived tokens, never stored in environment variables or Kubernetes Secrets.

**DB password in Secrets Manager**: Terraform generates a random password, stores it in Secrets Manager, and passes it to RDS. INSTRUCTIONS.md step 8 documents pulling the secret to create the K8s Secret. For production, use External Secrets Operator to automate this sync.

**Multi-stage Dockerfiles**: dependency layer cached separately from source — faster CI rebuilds when only source changes.

**Prometheus + Grafana via kube-prometheus-stack**: The `prometheus-community/kube-prometheus-stack` Helm chart installs Prometheus, Grafana, node-exporter, and kube-state-metrics in one release (namespace: `monitoring`). Spring Boot services expose `/actuator/prometheus` via `micrometer-registry-prometheus` (Spring Boot BOM manages the version). The frontend uses an `nginx/nginx-prometheus-exporter:1.1.0` sidecar that polls nginx `stub_status` on `http://localhost/nginx_status` and re-exposes the data in Prometheus format on port 9113. `serviceMonitorSelectorNilUsesHelmValues: false` in `values.yaml` is the key setting — it allows Prometheus to discover ServiceMonitor resources in the `digital-library` namespace (not just `monitoring`). Access is via `kubectl port-forward` only — no public Ingress is created for monitoring. The Grafana JVM dashboard (ID 11378) is pre-loaded via `values.yaml`.

## The 3 Interview Deliverables

1. **Cloud architecture** — EKS cluster, VPC with public/private subnets, ALB, SQS, RDS MySQL, ECR, IAM/IRSA
2. **Environment model** — dev/test (spot, single-AZ, 1 NAT GW) vs prod (on-demand, Multi-AZ, 2 NAT GWs), separate VPCs with non-overlapping CIDRs
3. **CI/CD pipeline** — GitHub Actions → ECR push → `kubectl set image` → rollout status; Terraform applied manually per environment

## AWS Credentials

**Local development**: uses the `Digital-Library` profile from `~/.aws/credentials`. Terraform and AWS CLI use `--profile Digital-Library`.

**CI/CD (GitHub Actions)**: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` env vars override the profile.

## CI/CD Secrets Required (GitHub → Settings → Secrets)

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | your 12-digit AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM user with ECR push + EKS describe permissions |
| `AWS_SECRET_ACCESS_KEY` | matching secret |

## Documentation Files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Architecture decisions, repo structure, commands |
| `INSTRUCTIONS.md` | Step-by-step deployment guide (bootstrap → running in prod) |
