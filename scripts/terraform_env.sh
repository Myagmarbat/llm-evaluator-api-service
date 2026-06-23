#!/usr/bin/env bash
# Shared Terraform/DigitalOcean environment helpers. Source from tf.sh and deploy.sh.

terraform_env_init() {
  ENVIRONMENT="${ENVIRONMENT:-dev}"
  export ENVIRONMENT
  export TF_VAR_environment="${ENVIRONMENT}"

  REGISTRY_NAME="${REGISTRY_NAME:-llmeval-dev}"
  export REGISTRY_NAME
  export IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-llm-evaluator-api-service}"
  export REGISTRY_REPO="${REGISTRY_REPO:-${IMAGE_REPOSITORY}}"

  STATE_DIR="${TERRAFORM_DIR}/state"
  mkdir -p "${STATE_DIR}"
  STATE_FILE="${STATE_DIR}/${ENVIRONMENT}.tfstate"

  if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" && ! -f "${STATE_FILE}" ]]; then
    echo "==> Migrating legacy terraform.tfstate to ${STATE_FILE}" >&2
    mv "${TERRAFORM_DIR}/terraform.tfstate" "${STATE_FILE}"
    if [[ -f "${TERRAFORM_DIR}/terraform.tfstate.backup" ]]; then
      mv "${TERRAFORM_DIR}/terraform.tfstate.backup" "${STATE_DIR}/${ENVIRONMENT}.tfstate.backup"
    fi
  fi

  terraform -chdir="${TERRAFORM_DIR}" init -input=false \
    -backend-config="path=state/${ENVIRONMENT}.tfstate" 2>"${STATE_DIR}/.init.err" || {
    if grep -q "Backend configuration changed" "${STATE_DIR}/.init.err" 2>/dev/null; then
      terraform -chdir="${TERRAFORM_DIR}" init -input=false \
        -backend-config="path=state/${ENVIRONMENT}.tfstate" -migrate-state
    else
      cat "${STATE_DIR}/.init.err" >&2
      return 1
    fi
  }

  echo "==> Environment: ${ENVIRONMENT} | registry: ${REGISTRY_NAME} | repo: ${IMAGE_REPOSITORY} | state: state/${ENVIRONMENT}.tfstate" >&2
}

registry_has_tag() {
  local tag="$1"
  doctl registry repository list-tags "${REGISTRY_REPO}" --no-header 2>/dev/null \
    | awk '{print $1}' | grep -Fxq "${tag}"
}

list_registry_tags() {
  doctl registry repository list-tags "${REGISTRY_REPO}" --no-header 2>/dev/null \
    | awk '{print $1}' | head -10
}

# Registry endpoint for docker push. Do not rely on `terraform output` here:
# after a targeted apply, outputs can be empty and Terraform may print warnings to stdout.
resolve_registry_endpoint() {
  local endpoint=""

  endpoint="$(doctl registry get "${REGISTRY_NAME}" --format Endpoint --no-header 2>/dev/null | tr -d '[:space:]')"
  if [[ "${endpoint}" =~ ^registry\.digitalocean\.com/.+ ]]; then
    printf '%s' "${endpoint}"
    return 0
  fi

  endpoint="$(doctl registry get --format Endpoint --no-header 2>/dev/null | tr -d '[:space:]')"
  if [[ "${endpoint}" =~ ^registry\.digitalocean\.com/.+ ]]; then
    printf '%s' "${endpoint}"
    return 0
  fi

  printf 'registry.digitalocean.com/%s' "${REGISTRY_NAME}"
}

resolve_app_url() {
  local app_name="llm-eval-api-${ENVIRONMENT}"
  local url=""

  url="$(terraform -chdir="${TERRAFORM_DIR}" output -raw app_url 2>/dev/null || true)"
  if [[ "${url}" =~ ^https:// ]]; then
    printf '%s' "${url}"
    return 0
  fi

  url="$(doctl apps list --format Spec.Name,DefaultIngress --no-header 2>/dev/null \
    | awk -v name="${app_name}" '$1 == name { print $2; exit }')"
  if [[ "${url}" =~ ^https:// ]]; then
    printf '%s' "${url}"
    return 0
  fi

  return 1
}
