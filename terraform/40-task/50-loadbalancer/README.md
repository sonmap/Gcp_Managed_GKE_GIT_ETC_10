# Namespace routing through the shared External HTTP Gateway

The shared external Application Load Balancer is bootstrapped in `30-foundation`:

- Gateway: `gateway-system/external-http-gateway`
- GatewayClass: `gke-l7-global-external-managed`
- Static public IP: `ip-sbx-external-gateway`
- Listener: HTTP port 80

Each task root creates its own namespace, Service, and HTTPRoute. For example:

- `jupyter-task01.sonmap.net` -> `task01/web-task01`
- `jupyter-task02.sonmap.net` -> `task02/web-task02`

Do not create a separate load balancer for every namespace. Attach additional HTTPRoute resources to the shared Gateway.

Add each test hostname and the shared external IP to the client hosts file. This POC uses HTTP and does not create DNS or TLS certificates.
