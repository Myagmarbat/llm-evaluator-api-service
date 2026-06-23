#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

if [[ -z "${TF_VAR_image_tag:-}" && -z "${IMAGE_TAG:-}" ]]; then
  if git -C "${ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    export TF_VAR_image_tag="$(git -C "${ROOT}" rev-parse HEAD)"
  else
    export TF_VAR_image_tag="latest"
  fi
else
  export TF_VAR_image_tag="${IMAGE_TAG:-${TF_VAR_image_tag}}"
fi

cd "${ROOT}/terraform"
exec terraform "$@"
