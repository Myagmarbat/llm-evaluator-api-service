#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT}/terraform"

# shellcheck disable=SC1091
source "${ROOT}/scripts/terraform_env.sh"

if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

export TF_VAR_do_token="${DIGITALOCEAN_TOKEN:-${TF_VAR_do_token:-}}"
export TF_VAR_inference_api_key="${INFERENCE_API_KEY:-${TF_VAR_inference_api_key:-}}"
export DIGITALOCEAN_ACCESS_TOKEN="${DIGITALOCEAN_TOKEN:-${DIGITALOCEAN_ACCESS_TOKEN:-}}"

if [[ -z "${TF_VAR_inference_api_key}" ]]; then
  echo "error: INFERENCE_API_KEY is required for App Platform deployment" >&2
  echo "hint: add INFERENCE_API_KEY to ${ROOT}/.env or export TF_VAR_inference_api_key" >&2
  exit 1
fi

if [[ -z "${TF_VAR_do_token}" ]]; then
  echo "error: DIGITALOCEAN_TOKEN is required" >&2
  echo "hint: add DIGITALOCEAN_TOKEN to ${ROOT}/.env or export TF_VAR_do_token" >&2
  exit 1
fi

if ! grep -q 'cpu_autoscaling_enabled' "${ROOT}/terraform/main.tf" 2>/dev/null; then
  echo "error: terraform/main.tf is outdated (missing autoscaling guard)" >&2
  echo "hint: run 'git pull origin main' and retry" >&2
  exit 1
fi

terraform_env_init

current_state_image_tag() {
  if ! terraform -chdir="${TERRAFORM_DIR}" state show digitalocean_app.main >/dev/null 2>&1; then
    return 0
  fi
  terraform -chdir="${TERRAFORM_DIR}" state show digitalocean_app.main \
    | sed -n 's/^[[:space:]]*tag[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

resolve_image_tag() {
  if [[ -n "${IMAGE_TAG:-}" ]]; then
    echo "${IMAGE_TAG}"
    return
  fi

  local state_tag
  state_tag="$(current_state_image_tag || true)"
  if [[ -n "${state_tag}" ]] && registry_has_tag "${state_tag}"; then
    echo "${state_tag}"
    return
  fi
  if [[ -n "${state_tag}" ]]; then
    echo "warning: state tag '${state_tag}' is not in DOCR; selecting a published tag instead" >&2
  fi

  if [[ -n "${TF_VAR_image_tag:-}" ]] && registry_has_tag "${TF_VAR_image_tag}"; then
    echo "${TF_VAR_image_tag}"
    return
  fi

  if registry_has_tag "latest"; then
    echo "latest"
    return
  fi

  local published_tag
  published_tag="$(list_registry_tags | head -1)"
  if [[ -n "${published_tag}" ]]; then
    echo "${published_tag}"
    return
  fi

  echo ""
}

terraform_var_file_args() {
  local tfvars="${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"
  if [[ -f "${tfvars}" ]]; then
    echo "-var-file=environments/${ENVIRONMENT}.tfvars"
  fi
}

TF_CMD="${1:-}"

if [[ "${TF_CMD}" == "apply" || "${TF_CMD}" == "plan" || "${TF_CMD}" == "destroy" || "${TF_CMD}" == "import" ]]; then
  export TF_VAR_image_tag="$(resolve_image_tag)"

  if [[ -z "${TF_VAR_image_tag}" ]]; then
    echo "error: could not determine image tag" >&2
    echo "hint: run ENVIRONMENT=${ENVIRONMENT} ./scripts/deploy.sh first, or set IMAGE_TAG" >&2
    exit 1
  fi

  if [[ "${TF_CMD}" == "apply" || "${TF_CMD}" == "plan" ]]; then
    if ! registry_has_tag "${TF_VAR_image_tag}"; then
      echo "error: image tag '${TF_VAR_image_tag}' not found in DOCR (${REGISTRY_REPO})" >&2
      echo "hint: run ENVIRONMENT=${ENVIRONMENT} ./scripts/deploy.sh to build and push" >&2
      echo "hint: or set IMAGE_TAG to an existing tag, for example:" >&2
      list_registry_tags | sed 's/^/  - /' >&2
      exit 1
    fi
    echo "==> Using image tag: ${TF_VAR_image_tag}" >&2
  fi
fi

case "${TF_CMD}" in
  apply|plan|destroy|import)
    VAR_FILE_ARGS="$(terraform_var_file_args)"
    # shellcheck disable=SC2086
    exec terraform -chdir="${TERRAFORM_DIR}" "$@" ${VAR_FILE_ARGS}
    ;;
  *)
    exec terraform -chdir="${TERRAFORM_DIR}" "$@"
    ;;
esac
