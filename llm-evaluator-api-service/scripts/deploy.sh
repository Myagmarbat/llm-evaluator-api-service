#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
IMAGE_REPO="llm-evaluator-api-service"
IMAGE_TAG="${IMAGE_TAG:-latest}"

: "${DIGITALOCEAN_TOKEN:?Set DIGITALOCEAN_TOKEN — a DigitalOcean API PAT (dop_v1_...), NOT the inference model access key}"
: "${INFERENCE_API_KEY:?Set INFERENCE_API_KEY — Model Access Key from Inference → Manage}"

export DIGITALOCEAN_TOKEN
export TF_VAR_do_token="$DIGITALOCEAN_TOKEN"
export TF_VAR_inference_api_key="$INFERENCE_API_KEY"

command -v terraform >/dev/null || { echo "terraform not found"; exit 1; }
command -v docker >/dev/null || { echo "docker not found"; exit 1; }
command -v doctl >/dev/null || { echo "doctl not found — install: https://docs.digitalocean.com/reference/doctl/"; exit 1; }

echo "Verifying DigitalOcean API token..."
doctl auth init -t "$DIGITALOCEAN_TOKEN" >/dev/null
doctl account get >/dev/null || {
  echo "ERROR: DIGITALOCEAN_TOKEN is invalid or lacks permissions (401)."
  echo "Create one at: Control Panel → API → Tokens (read + write)"
  exit 1
}

cd "$TF_DIR"
terraform init -input=false
terraform apply -auto-approve -input=false \
  -target=digitalocean_container_registry.this \
  -target=digitalocean_container_registry_docker_credentials.this

REGISTRY_ENDPOINT="$(terraform output -raw registry_endpoint)"
IMAGE="${REGISTRY_ENDPOINT}/${IMAGE_REPO}:${IMAGE_TAG}"

doctl registry login

docker build -t "${IMAGE}" -t "${REGISTRY_ENDPOINT}/${IMAGE_REPO}:latest" "$ROOT"
docker push "${IMAGE}"
docker push "${REGISTRY_ENDPOINT}/${IMAGE_REPO}:latest"

terraform apply -auto-approve -input=false -var="image_tag=${IMAGE_TAG}"

echo ""
echo "Deployed successfully."
echo "App URL: $(terraform output -raw app_url)"
echo "Image:   $(terraform output -raw image_reference)"
