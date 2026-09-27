# 30-foundation

This root creates the shared platform foundation and the common external HTTP entry point.

## Resources

- GKE Autopilot cluster with Gateway API enabled
- Global static external IP
- GKE global external managed Gateway on TCP port 80
- Artifact Registry repository
- Request / bundle buckets
- Cloud Run sandbox provisioner
- Eventarc approved-request trigger

## Execution boundary

- `admin@sonmap.net` performs only stages `10`, `20`, and `21`.
- Stage `30` is requested from `infra-son01` by the VM service account.
- Manual Cloud Build submissions for platform images use `sa-sbx-provisioner` impersonation.
- Infrastructure Manager stage `30` uses `sa-im-foundation`.
- Stage `40` is started by an approved request and uses the dedicated automation service accounts.

## Apply order

1. Re-apply `10-network-host` when Shared VPC or Gateway firewall changes are required.
2. Re-apply `20-admin-iam` and `21-enable-apis` when IAM/API definitions changed.
3. Build the Jupyter single-user image when `jupyter-singleuser-standard/` or `cloudbuild/build-jupyter-singleuser.yaml` changed.
4. Build the latest `cloudrun-provisioner` image when `cloudrun-provisioner/` changed.
5. Resolve the provisioner Artifact Registry digest and update both `provisioner_image` and `provisioner_release` in `terraform.auto.tfvars.json`.
6. Commit and push all synchronized source changes.
7. Update `im-sbx-foundation` to the exact Git commit through Infrastructure Manager.
8. Confirm that the new Cloud Run revision uses the same immutable provisioner digest.
9. Run `bash scripts/apply-30-external-gateway.sh` from `infra-son01` only when Gateway changes are required.
10. Apply the `40-task` flow for each sandbox request using the same approved Git commit SHA.

## Jupyter single-user image build

The standard user image is built before stage 40 so JupyterHub can reference the exact image tag defined in `cloudrun-provisioner/jupyterhub.py`.

```bash
gcloud builds submit . \
  --project=gcp-sbx-edp-gke01 \
  --region=asia-northeast3 \
  --config=cloudbuild/build-jupyter-singleuser.yaml \
  --substitutions=_REGISTRY=asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform \
  --impersonate-service-account=sa-sbx-provisioner@gcp-sbx-edp-gke01.iam.gserviceaccount.com
```

`sa-sbx-provisioner` requires Cloud Build submission, Service Usage, and Cloud Storage staging-bucket permissions. These permissions are managed in `terraform/20-admin-iam/main.tf`.

## Provisioner image synchronization

Do not rely on `sandbox-provisioner:latest` for the Cloud Run service. Artifact Registry can move the `latest` tag to a new digest while an existing Cloud Run revision continues to run the previous digest.

Build the provisioner with the same execution identity used for other stage-30 Cloud Build submissions:

```bash
gcloud builds submit . \
  --project=gcp-sbx-edp-gke01 \
  --region=asia-northeast3 \
  --config=cloudbuild/build-provisioner.yaml \
  --substitutions=_IMAGE_URI=asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner:latest \
  --impersonate-service-account=sa-sbx-provisioner@gcp-sbx-edp-gke01.iam.gserviceaccount.com
```

Check the new digest:

```bash
gcloud artifacts docker images describe \
  asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner:latest \
  --project=gcp-sbx-edp-gke01 \
  --format='value(image_summary.digest)'
```

Update `terraform.auto.tfvars.json`:

```json
{
  "provisioner_image": "asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner@sha256:<DIGEST>",
  "provisioner_release": "YYYYMMDD-releaseN"
}
```

Then commit/push and update `im-sbx-foundation` using that exact Git commit SHA:

```bash
cd ~/Gcp_Managed_GKE_GIT_ETC_10
git pull --ff-only origin main
GIT_SHA=$(git rev-parse HEAD)

gcloud infra-manager deployments apply im-sbx-foundation \
  --project=gcp-sbx-edp-gke01 \
  --location=asia-northeast3 \
  --service-account=projects/gcp-sbx-edp-gke01/serviceAccounts/sa-im-foundation@gcp-sbx-edp-gke01.iam.gserviceaccount.com \
  --git-source-repo=https://github.com/sonmap/Gcp_Managed_GKE_GIT_ETC_10.git \
  --git-source-directory=terraform/30-foundation \
  --git-source-ref="${GIT_SHA}"
```

The change in `provisioner_image` and `PROVISIONER_RELEASE` forces a new Cloud Run revision.

Confirm synchronization:

```bash
gcloud run revisions list \
  --service=run-sbx-provisioner \
  --project=gcp-sbx-edp-gke01 \
  --region=asia-northeast3 \
  --format='table(metadata.name,spec.containers[0].image,status.imageDigest)'
```

The newest Cloud Run revision digest must be identical to the digest configured in `terraform.auto.tfvars.json`.

## Gateway

The Gateway uses one external Application Load Balancer. Each task adds an HTTPRoute instead of creating another load balancer.

`infra-son01` is moved to `subnet-prod-edp-infra-admin-an3` (`172.32.10.0/24`) in `vpc-prod-edp-hub`, which is the same VPC used by GKE. Because this range isn't accepted in the PSC private endpoint authorized-network list, authorized networks aren't enforced on the private endpoint for this POC; IAM and Kubernetes RBAC are still enforced.
