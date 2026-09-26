#!/usr/bin/env bash
set -Eeuo pipefail

BASE_ACCOUNT="${BASE_ACCOUNT:-620081195575-compute@developer.gserviceaccount.com}"
GKE_ADMIN_SERVICE_ACCOUNT="${GKE_ADMIN_SERVICE_ACCOUNT:-sa-im-gke-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com}"

gcloud config set account "${BASE_ACCOUNT}" >/dev/null
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="${GKE_ADMIN_SERVICE_ACCOUNT}"
unset GOOGLE_OAUTH_ACCESS_TOKEN

exec terraform "$@"
