# Digital Library — AWS Cloud Migration

A cloud-native migration of an on-premise Digital Library platform to AWS. Built as a monorepo containing a React frontend and two Java microservices, wired together locally via Docker Compose and deployed to AWS ECS Fargate via GitHub Actions.

## Architecture

```
Employees → Library Portal (React) → Compressor → [Message Broker] → Worker → Database
```

| Component | Local | AWS |
|---|---|---|
| Library Portal | Vite dev server / nginx | CloudFront + S3 |
| Compressor | Spring Boot :8081 | ECS Fargate |
| Worker | Spring Boot :8082 | ECS Fargate |
| Message Broker | RabbitMQ | Amazon SQS |
| Database | PostgreSQL | Amazon RDS (PostgreSQL) |
| Container Registry | — | Amazon ECR |

## Repository Structure

```
.
├── frontend/               # React/Vite — Library Portal UI
├── compressor/             # Spring Boot — compresses PDFs, publishes to broker
├── worker/                 # Spring Boot — consumes from broker, persists to DB
├── infra/                  # Terraform IaC
│   ├── environments/       # dev / test / prod variable sets
│   └── modules/            # ecs, sqs, rds, s3, alb
└── .github/workflows/
    ├── ci.yml              # build + test on every push
    └── cd.yml              # push to ECR, deploy to ECS Fargate
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
mvn spring-boot:run
```

### Worker
```bash
cd worker
mvn spring-boot:run
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
cd compressor && mvn test

# Worker
cd worker && mvn test

# Frontend
cd frontend && npm run build
```

## CI/CD

- **CI** triggers on every push — builds and tests all three services in parallel
- **CD** triggers on merge to `main` — builds Docker images, pushes to ECR, deploys to ECS Fargate

Promotion path: `dev` → `test` → `prod` (manual approval gate before prod)

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCOUNT_ID` | AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM key with ECR push + ECS deploy permissions |
| `AWS_SECRET_ACCESS_KEY` | Matching IAM secret |

## Non-Functional Requirements

- **IaC** — all infrastructure managed via Terraform
- **Observability** — Spring Actuator `/health` and `/metrics` endpoints on every service; CloudWatch in AWS
- **Scalability** — ECS Fargate auto-scaling based on SQS queue depth (Worker) and CPU/memory (Compressor)
- **Cost** — scales to zero when idle; Fargate Spot used for non-prod environments
