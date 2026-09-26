#!/usr/bin/env bash
set -Eeuo pipefail

# Cloud Identity is administered directly by the selected directory admin.
# Remove impersonation settings left by the GKE steps.
unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
unset GOOGLE_OAUTH_ACCESS_TOKEN

GROUP_EMAIL="${GROUP_EMAIL:-pgrp-gcp-sbx01@sonmap.net}"
ORGANIZATION="${ORGANIZATION:-sonmap.net}"
DISPLAY_NAME="${DISPLAY_NAME:-GCP Sandbox 01}"
MEMBERS=(
  "${USER01_EMAIL:-user01@sonmap.net}"
  "${USER02_EMAIL:-user02@sonmap.net}"
)

if gcloud identity groups describe "${GROUP_EMAIL}" >/dev/null 2>&1; then
  echo "Group already exists: ${GROUP_EMAIL}"
else
  gcloud identity groups create "${GROUP_EMAIL}" \
    --organization="${ORGANIZATION}" \
    --group-type=security \
    --display-name="${DISPLAY_NAME}" \
    --description="Sandbox task01 access group"
fi

for member_email in "${MEMBERS[@]}"; do
  if gcloud identity groups memberships describe \
    --group-email="${GROUP_EMAIL}" \
    --member-email="${member_email}" >/dev/null 2>&1; then
    echo "Membership already exists: ${member_email}"
  else
    gcloud identity groups memberships add \
      --group-email="${GROUP_EMAIL}" \
      --member-email="${member_email}"
  fi
done

gcloud identity groups memberships list \
  --group-email="${GROUP_EMAIL}" \
  --format="table(preferredMemberKey.id,roles.name)"
