#!/usr/bin/env bash
# Shared Terraform/DigitalOcean environment helpers. Source from tf.sh and deploy.sh.

terraform_env_init() {
  ENVIRONMENT="${ENVIRONMENT:-dev}"
  export ENVIRONMENT
  export TF_VAR_environment="${ENVIRONMENT}"

  REGISTRY_NAME="${REGISTRY_NAME:-llmeval-${ENVIRONMENT}}"
  export REGISTRY_NAME
  export REGISTRY_REPO="${REGISTRY_REPO:-${REGISTRY_NAME}/llm-evaluator-api-service}"

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

  echo "==> Environment: ${ENVIRONMENT} | registry: ${REGISTRY_NAME} | state: state/${ENVIRONMENT}.tfstate" >&2
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
