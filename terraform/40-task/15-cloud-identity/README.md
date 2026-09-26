# Cloud Identity group Terraform

This Terraform root creates `pgrp-gcp-sbx01@sonmap.net` as a security group and
adds the existing `user01@sonmap.net` and `user02@sonmap.net` accounts.

Before running it, a Google Workspace Super Admin must delegate the built-in
`Groups Administrator` role to
`sa-sandbox-group-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com` once.

Copy `terraform.auto.tfvars.json.example` to `terraform.auto.tfvars.json` and
replace `customer_id` with the Google Workspace customer ID. Then run:

```bash
./tf.sh init
./tf.sh plan -out=15-cloud-identity.tfplan
./tf.sh apply 15-cloud-identity.tfplan
```
