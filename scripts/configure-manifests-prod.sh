#!/usr/bin/env bash
# Renders Kubernetes manifests for prod by filling in all REPLACE_WITH_* placeholders
# with live values pulled from Terraform outputs.
#
# Output goes to infra/k8s-rendered/prod/ — source files in infra/k8s/ are never modified.
#
# Usage:
#   ./scripts/configure-manifests-prod.sh             # image tag = current git SHA
#   ./scripts/configure-manifests-prod.sh abc1234     # image tag = explicit value
#
# Prerequisites: terraform, jq, git — all other values come from Terraform state.
# Run from the repo root.

set -euo pipefail

ENVIRONMENT="prod"
TF_DIR="infra/environments/${ENVIRONMENT}"
SOURCE_DIR="infra/k8s"
RENDERED_DIR="infra/k8s-rendered/${ENVIRONMENT}"
IMAGE_TAG="${1:-latest}"

# Digital-Library profile is used for all AWS calls (terraform provider + AWS CLI)
export AWS_PROFILE="Digital-Library"

# ─── 1. Pull Terraform outputs ────────────────────────────────────────────────

echo "→ Reading Terraform outputs from ${TF_DIR} ..."

ECR_JSON=$(terraform -chdir="${TF_DIR}" output -json ecr_repository_urls)
FRONTEND_ECR=$(echo "${ECR_JSON}" | jq -r '.frontend')
COMPRESSOR_ECR=$(echo "${ECR_JSON}" | jq -r '.compressor')
WORKER_ECR=$(echo "${ECR_JSON}" | jq -r '.worker')

SQS_URL=$(terraform -chdir="${TF_DIR}" output -raw sqs_queue_url)
S3_BUCKET=$(terraform -chdir="${TF_DIR}" output -raw s3_bucket_name)
DB_HOST=$(terraform -chdir="${TF_DIR}" output -raw db_endpoint)
CERT_ARN=$(terraform -chdir="${TF_DIR}" output -raw certificate_arn)
COMPRESSOR_IRSA=$(terraform -chdir="${TF_DIR}" output -raw compressor_irsa_arn)
WORKER_IRSA=$(terraform -chdir="${TF_DIR}" output -raw worker_irsa_arn)

# Domain is environment-specific and not stored in Terraform state
APP_DOMAIN="444noresponse.com"

# ─── 2. Copy source manifests to rendered dir ─────────────────────────────────

echo "→ Rendering manifests to ${RENDERED_DIR} ..."
rm -rf "${RENDERED_DIR}"
mkdir -p "$(dirname "${RENDERED_DIR}")"
cp -r "${SOURCE_DIR}" "${RENDERED_DIR}"

# macOS-compatible in-place sed (BSD sed requires an explicit backup suffix with -i)
sedi() { sed -i '' "$@"; }

# ─── 3. Deployments — swap placeholder + :latest for real ECR URL + image tag ─

sedi "s|REPLACE_WITH_ECR_URI/digital-library/frontend:latest|${FRONTEND_ECR}:${IMAGE_TAG}|g" \
  "${RENDERED_DIR}/frontend/deployment.yaml"

sedi "s|REPLACE_WITH_ECR_URI/digital-library/compressor:latest|${COMPRESSOR_ECR}:${IMAGE_TAG}|g" \
  "${RENDERED_DIR}/compressor/deployment.yaml"

sedi "s|REPLACE_WITH_ECR_URI/digital-library/worker:latest|${WORKER_ECR}:${IMAGE_TAG}|g" \
  "${RENDERED_DIR}/worker/deployment.yaml"

# ─── 4. ConfigMaps ────────────────────────────────────────────────────────────

sedi "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_URL}|g"       "${RENDERED_DIR}/compressor/configmap.yaml"
sedi "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g"   "${RENDERED_DIR}/compressor/configmap.yaml"
sedi "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_URL}|g"       "${RENDERED_DIR}/worker/configmap.yaml"
sedi "s|REPLACE_WITH_S3_BUCKET_NAME|${S3_BUCKET}|g"   "${RENDERED_DIR}/worker/configmap.yaml"
sedi "s|REPLACE_WITH_DB_HOST|${DB_HOST}|g"             "${RENDERED_DIR}/worker/configmap.yaml"

# ─── 5. ServiceAccounts (IRSA annotations) ────────────────────────────────────

sedi "s|REPLACE_WITH_COMPRESSOR_IRSA_ARN|${COMPRESSOR_IRSA}|g" \
  "${RENDERED_DIR}/compressor/serviceaccount.yaml"

sedi "s|REPLACE_WITH_WORKER_IRSA_ARN|${WORKER_IRSA}|g" \
  "${RENDERED_DIR}/worker/serviceaccount.yaml"

# ─── 6. Ingress (certificate + hostname) ──────────────────────────────────────

sedi "s|REPLACE_WITH_CERT_ARN|${CERT_ARN}|g"     "${RENDERED_DIR}/frontend/ingress.yaml"
sedi "s|REPLACE_WITH_APP_DOMAIN|${APP_DOMAIN}|g"  "${RENDERED_DIR}/frontend/ingress.yaml"

# ─── 7. Worker ScaledObject (KEDA SQS trigger) ────────────────────────────────

sedi "s|REPLACE_WITH_SQS_QUEUE_URL|${SQS_URL}|g" "${RENDERED_DIR}/worker/scaledobject.yaml"

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ Rendered to ${RENDERED_DIR}  (IMAGE_TAG=${IMAGE_TAG})"
echo ""
echo "Apply with:"
echo "  kubectl apply -f ${RENDERED_DIR}/namespace.yaml"
echo "  kubectl apply -f ${RENDERED_DIR}/compressor/serviceaccount.yaml"
echo "  kubectl apply -f ${RENDERED_DIR}/worker/serviceaccount.yaml"
echo "  kubectl apply -f ${RENDERED_DIR}/compressor/"
echo "  kubectl apply -f ${RENDERED_DIR}/worker/"
echo "  kubectl apply -f ${RENDERED_DIR}/frontend/"
