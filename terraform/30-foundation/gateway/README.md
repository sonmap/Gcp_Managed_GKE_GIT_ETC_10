# 30 Gateway Terraform

This directory manages the Kubernetes Gateway objects created after the GKE cluster.

Run it only from `infra-son01`, because the GKE control-plane endpoint is private.
The global external IP remains managed by the parent `30-foundation` Infrastructure Manager deployment.

For an existing Gateway created by the old script, initialize and import it before planning:

```bash
chmod +x tf.sh
./tf.sh init
./tf.sh import kubernetes_namespace_v1.gateway_system gateway-system
./tf.sh import kubernetes_manifest.external_http_gateway \
  'apiVersion=gateway.networking.k8s.io/v1,kind=Gateway,namespace=gateway-system,name=external-http-gateway'
./tf.sh plan
```

`tf.sh` deliberately ignores a user ADC file and starts with the VM service
account before the Google provider impersonates the GKE administrator service
account.
