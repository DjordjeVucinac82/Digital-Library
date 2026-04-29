# Digital Library — AWS Cloud Migration

A cloud-native migration of an on-premise Digital Library platform to AWS. Built as a monorepo containing a React frontend and two Java microservices, wired together locally via Docker Compose and deployed to AWS EKS via GitHub Actions.

## Architecture

```
Employees → Library Portal (React) → Compressor → [Message Broker] → Worker → Database
```

| Component | Local | AWS |
|---|---|---|
| Library Portal | Vite dev server / nginx | nginx pod + ALB Ingress |
| Compressor | Spring Boot :8081 | EKS (Spring `aws` profile) |
| Worker | Spring Boot :8082 | EKS (Spring `aws` profile) |
| Message Broker | RabbitMQ | Amazon SQS |
| Database | PostgreSQL | Amazon RDS MySQL |
| Container Registry | — | Amazon ECR |
| DNS | — | Route 53 + external-dns |

nginx inside the frontend pod reverse-proxies `/api/*` to the Compressor ClusterIP service, so only one ALB is needed and the Compressor is never exposed to the internet.

## Repository Structure

```
.
├── frontend/               # React/Vite — Library Portal UI (nginx reverse proxy)
├── compressor/             # Spring Boot — compresses PDFs, publishes S3 key to SQS
├── worker/                 # Spring Boot — consumes from SQS, downloads from S3, persists to RDS
├── infra/
│   ├── bootstrap/          # S3 + DynamoDB for Terraform remote state (run once)
│   ├── environments/       # dev / prod variable sets + provider.tf (S3 backend)
│   └── modules/            # vpc, eks, ecr, iam, rds, s3, sqs
│       └── k8s/            # Kubernetes manifests (namespace, deployments, services, ingress)
└── .github/workflows/
    ├── ci.yml              # build + test on every push
    └── cd.yml              # push to ECR, deploy to EKS via kubectl set image
```

## Local Development

**Prerequisites:** Docker and Docker Compose

```bash
docker-compose up --build
```

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Compressor API | http://localhost:8081/actuator/health |
| Worker API | http://localhost:8082/actuator/health |
| RabbitMQ UI | http://localhost:15672 (guest / guest) |

```bash
docker-compose down -v    # stop and remove volumes
```

## Running Services Individually

### Compressor
```bash
cd compressor
mvn spring-boot:run    # needs RabbitMQ on localhost:5672 (local Spring profile)
```

### Worker
```bash
cd worker
mvn spring-boot:run    # needs RabbitMQ + PostgreSQL (local Spring profile)
```

### Frontend
```bash
cd frontend
npm install
npm run dev    # http://localhost:5173
```

## Running Tests

```bash
# Compressor
cd compressor && mvn verify

# Worker
cd worker && mvn verify

# Frontend
cd frontend && npm run build
```

## CI/CD

- **CI** triggers on every push — builds and tests all three services in parallel
- **CD** triggers on merge to `main` — builds Docker images, pushes to ECR, deploys to EKS via `kubectl set image` + rollout status

Promotion path: `dev` → `prod` (Terraform applied manually per environment; `test` environment available)

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCOUNT_ID` | AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM key with ECR push + EKS describe permissions |
| `AWS_SECRET_ACCESS_KEY` | Matching IAM secret |

## Non-Functional Requirements

- **IaC** — all infrastructure managed via Terraform; remote state in S3 + DynamoDB lock
- **Observability** — Spring Actuator `/health` and `/metrics` on every service; logs to CloudWatch
- **Scalability** — HPA (CPU-based) for frontend + compressor; KEDA SQS scaler for worker; Cluster Autoscaler for nodes; PodDisruptionBudgets (minAvailable=1) on all services
- **Security** — IRSA (IAM Roles for Service Accounts); short-lived credentials, never stored in K8s Secrets; DB password in Secrets Manager
- **Cost** — dev/test use Spot instances + single NAT Gateway (~$72/month per EKS control plane); prod uses on-demand + Multi-AZ
