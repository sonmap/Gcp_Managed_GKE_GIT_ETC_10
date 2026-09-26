#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-sbx-edp-gke01}"
CERT_FILE="${1:?usage: $0 CERT_FILE KEY_FILE}"
KEY_FILE="${2:?usage: $0 CERT_FILE KEY_FILE}"

read -r -p "Google OAuth Client ID: " OAUTH_CLIENT_ID
read -r -s -p "Google OAuth Client Secret: " OAUTH_CLIENT_SECRET
printf '\n'

printf '%s' "${OAUTH_CLIENT_ID}" | gcloud secrets versions add jupyter-oauth-client-id \
  --project="${PROJECT_ID}" --data-file=-
printf '%s' "${OAUTH_CLIENT_SECRET}" | gcloud secrets versions add jupyter-oauth-client-secret \
  --project="${PROJECT_ID}" --data-file=-
gcloud secrets versions add jupyter-tls-cert \
  --project="${PROJECT_ID}" --data-file="${CERT_FILE}"
gcloud secrets versions add jupyter-tls-key \
  --project="${PROJECT_ID}" --data-file="${KEY_FILE}"

echo "JupyterHub OAuth and TLS secret versions were added."
