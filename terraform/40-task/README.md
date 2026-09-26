# Stage 40 task automation

Stage 40 is started by uploading an approved JSON file to the request bucket.

1. Eventarc invokes `run-sbx-provisioner` for `approved/*.json` objects.
2. Cloud Run creates or updates `im-<task>` from `terraform/40-task/im`.
3. Infrastructure Manager manages the project lookup/creation, APIs, project IAM,
   BigQuery, GCS and the Jupyter Google service account.
4. After the Infrastructure Manager operation completes, Cloud Run connects to
   the private GKE endpoint over Direct VPC egress and applies the namespace,
   KSA, quota, policies, test workload, Service and HTTPRoute.

`15-cloud-identity` is the Workspace bootstrap root. Existing groups and members
are reused by their email address. A Workspace Super Admin must assign the
Groups Administrator role to `sa-sandbox-group-admin` once; normal task runs do
not use the administrator account.

For the current POC, `gcp-sbx-edp-comn-509423` already exists, so the approved
request must use `"create_project": false`. The unified Infrastructure Manager
root reads the existing project and safely ensures the existing IAM member.

Upload pattern:

```bash
gcloud storage cp examples/task01-approved-request.json \
  gs://gcp-sbx-edp-gke01-requests/approved/task01.json
```
