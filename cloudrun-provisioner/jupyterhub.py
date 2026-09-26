import base64
import json
import os
import subprocess
import tempfile

import google.auth
from google.auth import impersonated_credentials
from google.auth.transport.requests import AuthorizedSession, Request as AuthRequest
from google.cloud import secretmanager
from kubernetes import client


def _base_credentials():
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    return credentials


def _secret(project_id: str, secret_id: str) -> str:
    api = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    return api.access_secret_version(request={"name": name}).payload.data.decode("utf-8")


def _run(command: list[str], env: dict) -> None:
    result = subprocess.run(command, env=env, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(
            f"command failed: {' '.join(command)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def _kube_clients(document: dict):
    gke = document["gke"]
    credentials = impersonated_credentials.Credentials(
        source_credentials=_base_credentials(),
        target_principal=os.environ["GKE_ADMIN_SERVICE_ACCOUNT"],
        target_scopes=["https://www.googleapis.com/auth/cloud-platform"],
        lifetime=3600,
    )
    credentials.refresh(AuthRequest())
    session = AuthorizedSession(credentials)
    url = (
        "https://container.googleapis.com/v1/projects/"
        f"{gke['project_id']}/locations/{gke['location']}/clusters/{gke['cluster_name']}"
    )
    response = session.get(url, timeout=60)
    response.raise_for_status()
    cluster = response.json()

    ca_data = cluster["masterAuth"]["clusterCaCertificate"]
    endpoint = cluster["privateClusterConfig"]["privateEndpoint"]
    kubeconfig = tempfile.NamedTemporaryFile(mode="w", delete=False)
    json.dump(
        {
            "apiVersion": "v1",
            "kind": "Config",
            "clusters": [{
                "name": "gke",
                "cluster": {
                    "server": f"https://{endpoint}",
                    "certificate-authority-data": ca_data,
                },
            }],
            "contexts": [{
                "name": "gke",
                "context": {"cluster": "gke", "user": "gke"},
            }],
            "current-context": "gke",
            "users": [{"name": "gke", "user": {"token": credentials.token}}],
        },
        kubeconfig,
    )
    kubeconfig.close()

    ca_file = tempfile.NamedTemporaryFile(delete=False)
    ca_file.write(base64.b64decode(ca_data))
    ca_file.close()
    configuration = client.Configuration()
    configuration.host = f"https://{endpoint}"
    configuration.ssl_ca_cert = ca_file.name
    configuration.api_key = {"authorization": f"Bearer {credentials.token}"}
    api_client = client.ApiClient(configuration)
    return api_client, kubeconfig.name


def apply_jupyterhub(document: dict) -> None:
    platform_project = os.environ["PLATFORM_PROJECT_ID"]
    task = document["task"]["name"]
    namespace = document["gke"]["namespace"]
    hostname = document["gke"]["jupyter_domain"]
    ksa = f"ksa-jupyter-{task}"
    api_client, kubeconfig = _kube_clients(document)
    core = client.CoreV1Api(api_client)
    apps = client.AppsV1Api(api_client)
    networking = client.NetworkingV1Api(api_client)
    custom = client.CustomObjectsApi(api_client)

    oauth_client_id = _secret(platform_project, "jupyter-oauth-client-id")
    oauth_client_secret = _secret(platform_project, "jupyter-oauth-client-secret")
    tls_cert = _secret(platform_project, "jupyter-tls-cert")
    tls_key = _secret(platform_project, "jupyter-tls-key")

    tls_name = f"tls-{task}"
    tls = client.V1Secret(
        metadata=client.V1ObjectMeta(name=tls_name, namespace="gateway-system"),
        type="kubernetes.io/tls",
        string_data={"tls.crt": tls_cert, "tls.key": tls_key},
    )
    try:
        core.read_namespaced_secret(tls_name, "gateway-system")
        core.patch_namespaced_secret(tls_name, "gateway-system", tls)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        core.create_namespaced_secret("gateway-system", tls)

    gateway = custom.get_namespaced_custom_object(
        "gateway.networking.k8s.io",
        "v1",
        "gateway-system",
        "gateways",
        "external-http-gateway",
    )
    listener_name = f"https-{task}"
    listeners = [
        item for item in gateway["spec"].get("listeners", [])
        if item.get("name") != listener_name
    ]
    listeners.append(
        {
            "name": listener_name,
            "protocol": "HTTPS",
            "port": 443,
            "hostname": hostname,
            "tls": {
                "mode": "Terminate",
                "certificateRefs": [{
                    "group": "",
                    "kind": "Secret",
                    "name": tls_name,
                }],
            },
            "allowedRoutes": {
                "namespaces": {"from": "All"},
            },
        }
    )
    custom.patch_namespaced_custom_object(
        "gateway.networking.k8s.io",
        "v1",
        "gateway-system",
        "gateways",
        "external-http-gateway",
        {"spec": {"listeners": listeners}},
    )

    allowed_users = document["identity"]["members"]
    values = {
        "hub": {
            "config": {
                "JupyterHub": {"authenticator_class": "google"},
                "Authenticator": {
                    "allow_all": False,
                    "allowed_users": allowed_users,
                },
                "GoogleOAuthenticator": {
                    "client_id": oauth_client_id,
                    "client_secret": oauth_client_secret,
                    "oauth_callback_url": f"https://{hostname}/hub/oauth_callback",
                    "hosted_domain": ["sonmap.net"],
                    "strip_domain": False,
                    "login_service": "Sonmap Google Account",
                },
            },
            "resources": {
                "requests": {"cpu": "500m", "memory": "1Gi"},
                "limits": {"cpu": "1", "memory": "2Gi"},
            },
        },
        "proxy": {
            "service": {"type": "ClusterIP"},
            "chp": {
                "resources": {
                    "requests": {"cpu": "500m", "memory": "512Mi"},
                    "limits": {"cpu": "500m", "memory": "1Gi"},
                },
            },
        },
        "singleuser": {
            "image": {
                "name": "quay.io/jupyterhub/k8s-singleuser-sample",
                "tag": "4.2.0",
            },
            "serviceAccountName": ksa,
            "cpu": {"guarantee": 1, "limit": 2},
            "memory": {"guarantee": "8G", "limit": "16G"},
            "storage": {
                "type": "dynamic",
                "capacity": "40Gi",
                "dynamic": {"storageClass": "standard-rwo"},
            },
            "cloudMetadata": {"blockWithIptables": False},
            "networkPolicy": {
                "enabled": True,
                "egressAllowRules": {"cloudMetadataServer": True},
            },
        },
        "prePuller": {"hook": {"enabled": False}, "continuous": {"enabled": False}},
        "scheduling": {"userScheduler": {"enabled": False}},
        "cull": {"enabled": True, "timeout": 3600},
    }
    values_file = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
    json.dump(values, values_file)
    values_file.close()
    child_env = dict(os.environ)
    child_env["KUBECONFIG"] = kubeconfig
    _run(
        [
            "helm", "repo", "add", "jupyterhub",
            "https://hub.jupyter.org/helm-chart/",
            "--force-update",
        ],
        child_env,
    )
    _run(["helm", "repo", "update"], child_env)
    _run(
        [
            "helm", "upgrade", "--install", f"jupyterhub-{task}",
            "jupyterhub/jupyterhub",
            "--version", "4.2.0",
            "--namespace", namespace,
            "--values", values_file.name,
            "--atomic", "--wait", "--timeout", "15m",
        ],
        child_env,
    )

    route_name = f"route-{task}"
    route_patch = {
        "spec": {
            "parentRefs": [{
                "name": "external-http-gateway",
                "namespace": "gateway-system",
                "sectionName": listener_name,
            }],
            "hostnames": [hostname],
            "rules": [{"backendRefs": [{"name": "proxy-public", "port": 80}]}],
        }
    }
    custom.patch_namespaced_custom_object(
        "gateway.networking.k8s.io",
        "v1",
        namespace,
        "httproutes",
        route_name,
        route_patch,
    )

    for policy in ["default-deny-ingress", "allow-gateway-to-test-web"]:
        try:
            networking.delete_namespaced_network_policy(policy, namespace)
        except client.ApiException as exc:
            if exc.status != 404:
                raise
    try:
        apps.delete_namespaced_deployment(f"web-{task}", namespace)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
    try:
        core.delete_namespaced_service(f"web-{task}", namespace)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
