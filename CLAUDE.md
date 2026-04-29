# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This workspace is for preparing a final technical interview at Zühlke (DevOps/Cloud Engineer role). The deliverable is a 60-minute presentation: 25 min presentation + 35 min Q&A with a technical Zühlke dev team and clients.

## The Case Study

**Digital Library** — migrate an existing on-premise 3-tier application to AWS with minimal cost and maintenance effort, then optimize for cloud-native benefits.

### Application flow

```
Employees → Library Portal (React) → Compressor (Java) → Message Broker → Worker (Java) → Database (binary)
```

- **Library Portal** (`frontend/`): React/Vite app — employees upload PDF books, served via nginx
- **Compressor** (`compressor/`): Spring Boot on port 8081 — receives PDFs via REST, GZIP-compresses them, publishes to `books.compressed` queue
- **Worker** (`worker/`): Spring Boot on port 8082 — listens on queue, persists compressed binary to PostgreSQL
- **Message Broker**: RabbitMQ locally → Amazon SQS in AWS
- **Database**: PostgreSQL locally → Amazon RDS in AWS

### Non-functional requirements (from the brief)

- Infrastructure as Code is mandatory
- Observable at every service boundary
- Auto-scaling: scale up under load, scale down when idle — cost-effectively
- Quality assurance is business critical

## Repository Structure

```
Zuhlke-library/
├── frontend/           # React/Vite — Library Portal
├── compressor/         # Java/Spring Boot — PDF compressor microservice
├── worker/             # Java/Spring Boot — DB writer microservice
├── infra/              # Terraform (to be built out)
│   ├── environments/   # dev / test / prod tfvars
│   └── modules/        # ecs, sqs, rds, s3, alb
├── .github/workflows/
│   ├── ci.yml          # build + test all three services on every push
│   └── cd.yml          # build Docker images, push to ECR, deploy to ECS Fargate
└── docker-compose.yml  # full local stack (RabbitMQ + PostgreSQL + all services)
```

## Commands

### Local development (all services together)
```bash
docker-compose up --build          # start full stack
docker-compose down -v             # stop and remove volumes
```

RabbitMQ management UI: http://localhost:15672 (guest/guest)
Frontend: http://localhost:3000
Compressor API: http://localhost:8081/actuator/health
Worker API: http://localhost:8082/actuator/health

### Compressor microservice
```bash
cd compressor
mvn verify                         # build + run tests
mvn spring-boot:run                # run locally (needs RabbitMQ on localhost:5672)
mvn test -Dtest=CompressorServiceTest   # run single test class
```

### Worker microservice
```bash
cd worker
mvn verify
mvn spring-boot:run                # needs RabbitMQ + PostgreSQL
mvn test -Dtest=BookStorageServiceTest
```

### Frontend
```bash
cd frontend
npm install
npm run dev                        # Vite dev server on http://localhost:5173
npm run build                      # production build to dist/
```

## Architecture Decisions

**Why monorepo**: single CI/CD pipeline, easier to demo full system in one repo for the interview scope. In production with multiple teams, would split into per-service repos for independent release cycles.

**Local broker (RabbitMQ) → AWS (SQS)**: The `application.yml` in both services uses environment variables for broker connection. In AWS, the `@RabbitListener` in Worker is replaced with Spring Cloud AWS `@SqsListener` — the service logic stays identical.

**ECS Fargate over EKS**: lower operational overhead, no control plane to manage, scales to zero, better cost profile for startup scale (10–20 users/day initially). EKS makes sense when you need custom scheduling or have 10+ services.

**Multi-stage Dockerfiles**: dependency layer is cached separately from source layer — significantly faster CI rebuilds when only source changes.

## The 3 Interview Deliverables

1. **Cloud architecture** — AWS service mapping, security, observability
2. **Environment model** — how dev/test/prod are separated (AWS accounts vs VPCs)
3. **CI/CD pipeline** — tool choices, promotion strategy, quality gates, rollback

## CI/CD Secrets Required (GitHub → Settings → Secrets)

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | your AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM user with ECR push + ECS deploy permissions |
| `AWS_SECRET_ACCESS_KEY` | matching secret |
