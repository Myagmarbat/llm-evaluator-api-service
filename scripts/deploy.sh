#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/terraform_env.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PROJECT_NAME="${PROJECT_NAME:-llm-evaluator-api-service}"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env"
  set +a
fi

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
  echo "error: DIGITALOCEAN_TOKEN is required" >&2
  exit 1
fi

if [[ -z "${INFERENCE_API_KEY:-}" ]]; then
  echo "error: INFERENCE_API_KEY is required" >&2
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
export DIGITALOCEAN_ACCESS_TOKEN="${DIGITALOCEAN_TOKEN}"
if ! doctl account get >/dev/null 2>&1; then
  echo "error: doctl could not authenticate with DIGITALOCEAN_TOKEN" >&2
  exit 1
fi

export TF_VAR_do_token="${DIGITALOCEAN_TOKEN}"
export TF_VAR_inference_api_key="${INFERENCE_API_KEY}"
export TF_VAR_image_tag="${IMAGE_TAG}"

terraform_env_init

terraform_var_file_args() {
  local tfvars="${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"
  if [[ -f "${tfvars}" ]]; then
    echo "-var-file=environments/${ENVIRONMENT}.tfvars"
  fi
}

VAR_FILE_ARGS="$(terraform_var_file_args)"

import_if_missing() {
  local resource="$1"
  local id="$2"
  if ! terraform -chdir="${TERRAFORM_DIR}" state show "${resource}" >/dev/null 2>&1; then
    terraform -chdir="${TERRAFORM_DIR}" import "${resource}" "${id}" >/dev/null 2>&1 || true
  fi
}

echo "==> Applying container registry..."
import_if_missing digitalocean_container_registry.main "${REGISTRY_NAME}"
import_if_missing digitalocean_container_registry_docker_credentials.main "${REGISTRY_NAME}"
# shellcheck disable=SC2086
terraform -chdir="${TERRAFORM_DIR}" apply \
  ${VAR_FILE_ARGS} \
  -target=digitalocean_container_registry.main \
  -target=digitalocean_container_registry_docker_credentials.main \
  -auto-approve

REGISTRY_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw registry_endpoint)"
IMAGE="${REGISTRY_ENDPOINT}/${PROJECT_NAME}:${IMAGE_TAG}"

echo "==> Building and pushing ${IMAGE}..."
doctl registry login
docker build -t "${IMAGE}" -t "${REGISTRY_ENDPOINT}/${PROJECT_NAME}:latest" "${PROJECT_ROOT}"
docker push "${IMAGE}"
docker push "${REGISTRY_ENDPOINT}/${PROJECT_NAME}:latest"

echo "==> Applying App Platform service..."
# shellcheck disable=SC2086
terraform -chdir="${TERRAFORM_DIR}" apply ${VAR_FILE_ARGS} -auto-approve

APP_URL="$(terraform -chdir="${TERRAFORM_DIR}" output -raw app_url)"
echo "==> Deployed successfully (${ENVIRONMENT}): ${APP_URL}"
