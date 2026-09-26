#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-sbx-edp-gke01}"
REGION="${REGION:-asia-northeast3}"
CLUSTER_NAME="${CLUSTER_NAME:-gke-sbx-edp-main-an3}"
GKE_ADMIN_SERVICE_ACCOUNT="${GKE_ADMIN_SERVICE_ACCOUNT:-sa-im-gke-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
GATEWAY_MANIFEST="${REPO_ROOT}/terraform/30-foundation/external-gateway.yaml"

for command_name in gcloud kubectl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${GKE_ADMIN_SERVICE_ACCOUNT}"

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --internal-ip

if ! kubectl --request-timeout=15s get --raw=/readyz >/dev/null; then
  echo "Cannot reach the GKE private endpoint. Check the VM network and routes." >&2
  exit 1
fi

for attempt in $(seq 1 30); do
  if kubectl --request-timeout=15s get gatewayclass gke-l7-global-external-managed >/dev/null 2>&1; then
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    echo "GatewayClass is not ready. Retry this script after a few minutes." >&2
    exit 1
  fi

  echo "Waiting for GatewayClass (${attempt}/30)..."
  sleep 10
done

kubectl apply -f "${GATEWAY_MANIFEST}"
kubectl get gateway external-http-gateway -n gateway-system
