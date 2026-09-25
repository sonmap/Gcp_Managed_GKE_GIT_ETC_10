# Namespace routing through the shared External HTTPS Gateway

The shared external Application Load Balancer is bootstrapped in `30-foundation`:

- Gateway: `gateway-system/external-https-gateway`
- GatewayClass: `gke-l7-global-external-managed`
- Static public IP: `ip-sbx-external-gateway`
- Certificate map: `cm-sbx-external-gateway`
- Public DNS zone: `gke.sonmap.net`

Each task root creates its own namespace, Service, and HTTPRoute. For example:

- `task01.gke.sonmap.net` -> `task01/web-task01`
- `task02.gke.sonmap.net` -> `task02/web-task02`

Do not create a separate load balancer for every namespace. Attach additional HTTPRoute resources to the shared Gateway.

The parent `sonmap.net` DNS must delegate `gke.sonmap.net` to the Cloud DNS name servers output by `30-foundation`.
