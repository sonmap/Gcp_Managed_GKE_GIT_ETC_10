#!/usr/bin/env bash
set -euo pipefail

HOST_PROJECT_ID="${1:-gcp-prod-edp-hub-vpchost}"

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  serviceusage.googleapis.com \
  servicenetworking.googleapis.com \
  --project="${HOST_PROJECT_ID}"

gcloud beta services identity create \
  --service=container.googleapis.com \
  --project="${HOST_PROJECT_ID}"
