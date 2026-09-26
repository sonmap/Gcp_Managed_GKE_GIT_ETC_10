# Cloud Identity group bootstrap

Run this once with a Google Workspace or Cloud Identity administrator account.

```bash
gcloud config set account admin@sonmap.net
gcloud services enable cloudidentity.googleapis.com --project=gcp-sbx-edp-gke01
./create-group.sh
```

The script creates `pgrp-gcp-sbx01@sonmap.net` as a security group and adds
`user01@sonmap.net` and `user02@sonmap.net`. Re-running it is safe.
