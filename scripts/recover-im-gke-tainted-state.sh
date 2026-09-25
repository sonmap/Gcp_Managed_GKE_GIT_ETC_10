#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-sbx-edp-gke01}"
LOCATION="${LOCATION:-asia-northeast3}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-im-sbx-foundation}"
RESOURCE_ADDRESS="${RESOURCE_ADDRESS:-google_container_cluster.main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/terraform/30-foundation"
WORK_DIR="$(mktemp -d)"
WORK_STATE="${WORK_DIR}/terraform.tfstate"
BACKUP_STATE="/tmp/${DEPLOYMENT_ID}-before-untaint-$(date +%Y%m%d%H%M%S).tfstate"
LOCK_ID=""

cleanup() {
  local exit_code=$?
  if [[ -n "${LOCK_ID}" ]]; then
    gcloud infra-manager deployments unlock "${DEPLOYMENT_ID}"       --project="${PROJECT_ID}"       --location="${LOCATION}"       --lock-id="${LOCK_ID}" >/dev/null || true
  fi
  rm -rf -- "${WORK_DIR}"
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

for command_name in gcloud curl jq terraform; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

gcloud infra-manager deployments lock "${DEPLOYMENT_ID}"   --project="${PROJECT_ID}"   --location="${LOCATION}"

LOCK_ID="$(gcloud infra-manager deployments export-lock "${DEPLOYMENT_ID}"   --project="${PROJECT_ID}"   --location="${LOCATION}"   --format='value(lockId)')"

STATE_URL="$(gcloud infra-manager deployments export-statefile "${DEPLOYMENT_ID}"   --project="${PROJECT_ID}"   --location="${LOCATION}"   --format='value(signedUri)')"

curl -fsSL "${STATE_URL}" -o "${BACKUP_STATE}"
cp "${BACKUP_STATE}" "${WORK_STATE}"

CURRENT_STATUS="$(jq -r --arg address_name "main" '
  .resources[]
  | select(.type == "google_container_cluster" and .name == $address_name)
  | .instances[0].status // "managed"
' "${WORK_STATE}")"

CURRENT_PROTECTION="$(jq -r '
  .resources[]
  | select(.type == "google_container_cluster" and .name == "main")
  | .instances[0].attributes.deletion_protection
' "${WORK_STATE}")"

if [[ "${CURRENT_STATUS}" != "tainted" || "${CURRENT_PROTECTION}" != "true" ]]; then
  echo "Unexpected state: status=${CURRENT_STATUS}, deletion_protection=${CURRENT_PROTECTION}" >&2
  echo "No state change was uploaded." >&2
  exit 1
fi

cp "${CONFIG_DIR}"/*.tf "${WORK_DIR}/"
terraform -chdir="${WORK_DIR}" init -backend=false
terraform -chdir="${WORK_DIR}" untaint -state="${WORK_STATE}" "${RESOURCE_ADDRESS}"

UPDATED_STATUS="$(jq -r '
  .resources[]
  | select(.type == "google_container_cluster" and .name == "main")
  | .instances[0].status // "managed"
' "${WORK_STATE}")"

if [[ "${UPDATED_STATUS}" != "managed" ]]; then
  echo "Untaint validation failed: status=${UPDATED_STATUS}" >&2
  exit 1
fi

UPLOAD_URL="$(gcloud infra-manager deployments import-statefile "${DEPLOYMENT_ID}"   --project="${PROJECT_ID}"   --location="${LOCATION}"   --lock-id="${LOCK_ID}"   --format='value(signedUri)')"

curl -fsS -X PUT --upload-file "${WORK_STATE}" "${UPLOAD_URL}"

gcloud infra-manager deployments unlock "${DEPLOYMENT_ID}"   --project="${PROJECT_ID}"   --location="${LOCATION}"   --lock-id="${LOCK_ID}"
LOCK_ID=""

echo "State recovery completed."
echo "Backup: ${BACKUP_STATE}"
echo "Resource: ${RESOURCE_ADDRESS}"
echo "Status: managed"
