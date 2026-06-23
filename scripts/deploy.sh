#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

ENVIRONMENT="${ENVIRONMENT:-dev}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PROJECT_NAME="${PROJECT_NAME:-llm-evaluator-api-service}"

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
  echo "error: DIGITALOCEAN_TOKEN is required" >&2
  exit 1
fi

if ! command -v doctl >/dev/null 2>&1; then
  echo "error: doctl is required (https://docs.digitalocean.com/reference/doctl/)" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "error: terraform is required" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker CLI is required (https://docs.docker.com/get-docker/)" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "error: docker daemon is not running or not accessible" >&2
  echo "hint: start Docker Desktop or OrbStack on your host machine" >&2
  echo "hint: or deploy via GitHub Actions — the CD workflow builds and pushes the image on ubuntu-latest" >&2
  exit 1
fi

export DIGITALOCEAN_TOKEN
if ! doctl account get >/dev/null 2>&1; then
  echo "error: doctl could not authenticate with DIGITALOCEAN_TOKEN" >&2
  exit 1
fi

export TF_VAR_do_token="${DIGITALOCEAN_TOKEN}"
export TF_VAR_environment="${ENVIRONMENT}"
export TF_VAR_image_tag="${IMAGE_TAG}"

if [[ -n "${INFERENCE_API_KEY:-}" ]]; then
  export TF_VAR_inference_api_key="${INFERENCE_API_KEY}"
fi

cd "${TERRAFORM_DIR}"

echo "==> Applying container registry..."
terraform apply \
  -target=digitalocean_container_registry.main \
  -target=digitalocean_container_registry_docker_credentials.main \
  -auto-approve

REGISTRY_ENDPOINT="$(terraform output -raw registry_endpoint)"
REGISTRY_NAME="$(terraform output -raw registry_name)"
IMAGE="${REGISTRY_ENDPOINT}/${REGISTRY_NAME}/${PROJECT_NAME}:${IMAGE_TAG}"

echo "==> Building and pushing ${IMAGE}..."
doctl registry login
docker build -t "${IMAGE}" "${PROJECT_ROOT}"
docker push "${IMAGE}"

echo "==> Applying App Platform service..."
terraform apply -auto-approve

APP_URL="$(terraform output -raw app_url)"
echo "==> Deployed successfully: ${APP_URL}"
