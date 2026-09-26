# 30-foundation

This root creates the shared platform foundation and the common external HTTP entry point.

## Resources

- GKE Autopilot cluster with Gateway API enabled
- Global static external IP
- GKE global external managed Gateway on TCP port 80

## Apply order

1. Re-apply `10-network-host` for the Shared VPC Gateway health-check firewall rule.
2. Re-apply `20-admin-iam` and `21-enable-apis`.
3. Apply this root through Infrastructure Manager.
4. Run `bash scripts/apply-30-external-gateway.sh` from `infra-son01`.
5. Apply `terraform/40-task/40-gke` for each namespace route.
6. Add the output IP and `jupyter-task01.sonmap.net` to the client hosts file.

The Gateway uses one external Application Load Balancer. Each task adds an HTTPRoute instead of creating another load balancer.

This POC intentionally uses HTTP. Do not send passwords or production data over this endpoint.
