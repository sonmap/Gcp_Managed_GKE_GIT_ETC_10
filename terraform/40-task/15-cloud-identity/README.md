# Cloud Identity group bootstrap

Before stage 40, a Google Workspace Super Admin must delegate the built-in
`Groups Administrator` role to this service account once:

`sa-sandbox-group-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com`

Use the service account's numeric unique ID when creating the Admin SDK role
assignment. This is a directory bootstrap action, not a stage-40 execution.

After delegation, stage 40 runs only as the VM service account and impersonates
the group administrator service account:

```bash
gcloud config set account 620081195575-compute@developer.gserviceaccount.com
./create-group.sh
```

The script creates `pgrp-gcp-sbx01@sonmap.net` as a security group and adds
`user01@sonmap.net` and `user02@sonmap.net`. Re-running it is safe.
