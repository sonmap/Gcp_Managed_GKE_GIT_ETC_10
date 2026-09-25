# 30-foundation

This root creates the shared platform foundation and the common external HTTPS entry point.

## Resources

- GKE Autopilot cluster with Gateway API enabled
- Global static external IP
- Cloud DNS public zone for `gke.sonmap.net`
- Google-managed wildcard certificate for `*.gke.sonmap.net`
- Certificate Manager map used by the GKE Gateway

## Apply order

1. Re-apply `10-network-host` for the Shared VPC Gateway health-check firewall rule.
2. Re-apply `20-admin-iam` and `21-enable-apis`.
3. Apply this root through Infrastructure Manager.
4. Delegate `gke.sonmap.net` from the parent `sonmap.net` DNS to the output name servers.
5. Run `bash scripts/apply-30-external-gateway.sh` from `infra-son01`.
6. Apply `terraform/40-task/40-gke` for each namespace route.

The Gateway uses one external Application Load Balancer. Each task adds an HTTPRoute instead of creating another load balancer.
