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

## Apply order

1. Re-apply `10-network-host` for the Shared VPC Gateway health-check firewall rule.
2. Re-apply `20-admin-iam` and `21-enable-apis`.
3. Build the latest `cloudrun-provisioner` image with `cloudbuild/build-provisioner.yaml`.
4. Resolve the Artifact Registry image digest and update both `provisioner_image` and `provisioner_release` in `terraform.auto.tfvars.json`.
5. Commit and push the Git source.
6. Update `im-sbx-foundation` to the new Git commit through Infrastructure Manager.
7. Confirm that the new Cloud Run revision uses the same immutable image digest.
8. Run `bash scripts/apply-30-external-gateway.sh` from `infra-son01` when Gateway changes are required.
9. Apply the 40-task flow for each sandbox request.

## Provisioner image synchronization

Do not rely on `sandbox-provisioner:latest` for the Cloud Run service. Artifact Registry can move the `latest` tag to a new digest while an existing Cloud Run revision continues to run the previous digest.

The Terraform input therefore uses an immutable Artifact Registry digest, for example:

```text
asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner@sha256:<DIGEST>
```

After every provisioner source change:

```bash
gcloud builds submit . \
  --project=gcp-sbx-edp-gke01 \
  --region=asia-northeast3 \
  --config=cloudbuild/build-provisioner.yaml \
  --substitutions=_IMAGE_URI=asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner:latest
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

Then commit/push and update `im-sbx-foundation` using that exact Git commit SHA. The change in `provisioner_image` and `PROVISIONER_RELEASE` forces a new Cloud Run revision.

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
