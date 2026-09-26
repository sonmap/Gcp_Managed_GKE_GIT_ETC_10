#!/usr/bin/env bash
set -Eeuo pipefail

BASE_ACCOUNT="${BASE_ACCOUNT:-620081195575-compute@developer.gserviceaccount.com}"

for command_name in gcloud terraform; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

# Use the VM service account as the base credential. The Google provider then
# impersonates sa-im-gke-admin as configured in providers.tf.
unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
export GOOGLE_OAUTH_ACCESS_TOKEN
GOOGLE_OAUTH_ACCESS_TOKEN="$(
  gcloud auth print-access-token --account="${BASE_ACCOUNT}"
)"

exec terraform "$@"
