#!/usr/bin/env bash
set -Eeuo pipefail

BASE_ACCOUNT="${BASE_ACCOUNT:-620081195575-compute@developer.gserviceaccount.com}"

unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
export GOOGLE_OAUTH_ACCESS_TOKEN
GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account="${BASE_ACCOUNT}")"

exec terraform "$@"
