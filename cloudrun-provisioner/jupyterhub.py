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


GROUP_NAMESPACES = {
    "general": "jhub-general",
    "secret": "jhub-secret",
    "always": "jhub-always",
}

GROUP_DOMAIN_DEFAULTS = {
    "general": "jupyter-general.sonmap.net",
    "secret": "jupyter-secret.sonmap.net",
    "always": "jupyter-always.sonmap.net",
}


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


def _group_config(document: dict) -> tuple[str, str, str]:
    raw_group = str(document.get("task", {}).get("group", "general")).strip().lower()
    aliases = {
        "normal": "general",
        "general": "general",
        "secret": "secret",
        "always": "always",
    }
    group = aliases.get(raw_group)
    if group is None:
        raise ValueError("task.group must be one of: general, secret, always")

    namespace = GROUP_NAMESPACES[group]
    hostname = document.get("gke", {}).get("group_jupyter_domain")
    if not hostname:
        hostname = GROUP_DOMAIN_DEFAULTS[group]
    return group, namespace, hostname


def _ensure_namespace(core: client.CoreV1Api, namespace: str, labels: dict[str, str]) -> None:
    body = client.V1Namespace(
        metadata=client.V1ObjectMeta(name=namespace, labels=labels)
    )
    try:
        current = core.read_namespace(namespace)
        merged = dict(current.metadata.labels or {})
        merged.update(labels)
        body.metadata.labels = merged
        core.patch_namespace(namespace, body)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        core.create_namespace(body)


def _load_and_update_task_map(
    core: client.CoreV1Api,
    group_namespace: str,
    task_namespace: str,
    task: str,
    ksa: str,
    members: list[str],
) -> dict:
    name = "jupyterhub-task-map"
    mapping = {}
    try:
        current = core.read_namespaced_config_map(name, group_namespace)
        raw = (current.data or {}).get("mapping.json", "{}")
        mapping = json.loads(raw)
    except client.ApiException as exc:
        if exc.status != 404:
            raise

    for user in members:
        mapping[user] = {
            "task": task,
            "namespace": task_namespace,
            "ksa": ksa,
        }

    body = client.V1ConfigMap(
        metadata=client.V1ObjectMeta(name=name, namespace=group_namespace),
        data={"mapping.json": json.dumps(mapping, sort_keys=True)},
    )
    try:
        core.read_namespaced_config_map(name, group_namespace)
        core.patch_namespaced_config_map(name, group_namespace, body)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        core.create_namespaced_config_map(group_namespace, body)
    return mapping


def _ensure_task_rbac_and_network(
    api_client: client.ApiClient,
    task_namespace: str,
    group_namespace: str,
    group: str,
) -> None:
    core = client.CoreV1Api(api_client)
    rbac = client.RbacAuthorizationV1Api(api_client)
    networking = client.NetworkingV1Api(api_client)

    task_ns = core.read_namespace(task_namespace)
    labels = dict(task_ns.metadata.labels or {})
    labels.update({"jupyterhub-task": task_namespace, "jupyterhub-group": group})
    core.patch_namespace(
        task_namespace,
        client.V1Namespace(
            metadata=client.V1ObjectMeta(name=task_namespace, labels=labels)
        ),
    )

    role_name = "jupyterhub-spawner"
    role = client.V1Role(
        metadata=client.V1ObjectMeta(name=role_name, namespace=task_namespace),
        rules=[
            client.V1PolicyRule(
                api_groups=[""],
                resources=[
                    "pods",
                    "pods/log",
                    "services",
                    "persistentvolumeclaims",
                    "events",
                ],
                verbs=["get", "list", "watch", "create", "delete", "patch", "update"],
            )
        ],
    )
    try:
        rbac.read_namespaced_role(role_name, task_namespace)
        rbac.patch_namespaced_role(role_name, task_namespace, role)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        rbac.create_namespaced_role(task_namespace, role)

    binding_name = "jupyterhub-spawner"
    binding = client.V1RoleBinding(
        metadata=client.V1ObjectMeta(name=binding_name, namespace=task_namespace),
        role_ref=client.V1RoleRef(
            api_group="rbac.authorization.k8s.io",
            kind="Role",
            name=role_name,
        ),
        subjects=[
            client.V1Subject(
                kind="ServiceAccount",
                name="hub",
                namespace=group_namespace,
            )
        ],
    )
    try:
        rbac.read_namespaced_role_binding(binding_name, task_namespace)
        rbac.patch_namespaced_role_binding(binding_name, task_namespace, binding)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        rbac.create_namespaced_role_binding(task_namespace, binding)

    policy_name = "allow-jupyterhub-group"
    policy = client.V1NetworkPolicy(
        metadata=client.V1ObjectMeta(name=policy_name, namespace=task_namespace),
        spec=client.V1NetworkPolicySpec(
            pod_selector=client.V1LabelSelector(
                match_labels={"app": "jupyterhub", "component": "singleuser-server"}
            ),
            ingress=[
                client.V1NetworkPolicyIngressRule(
                    _from=[
                        client.V1NetworkPolicyPeer(
                            namespace_selector=client.V1LabelSelector(
                                match_labels={"jupyterhub-group": group}
                            )
                        )
                    ]
                )
            ],
            policy_types=["Ingress"],
        ),
    )
    try:
        networking.read_namespaced_network_policy(policy_name, task_namespace)
        networking.patch_namespaced_network_policy(policy_name, task_namespace, policy)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        networking.create_namespaced_network_policy(task_namespace, policy)


def apply_jupyterhub(document: dict) -> None:
    platform_project = os.environ["PLATFORM_PROJECT_ID"]
    task = document["task"]["name"]
    task_namespace = document["gke"]["namespace"]
    ksa = f"ksa-jupyter-{task}"
    group, group_namespace, hostname = _group_config(document)

    api_client, kubeconfig = _kube_clients(document)
    core = client.CoreV1Api(api_client)
    apps = client.AppsV1Api(api_client)
    networking = client.NetworkingV1Api(api_client)
    custom = client.CustomObjectsApi(api_client)

    _ensure_namespace(
        core,
        group_namespace,
        {"jupyterhub-group": group, "app.kubernetes.io/part-of": "jupyterhub"},
    )
    _ensure_task_rbac_and_network(api_client, task_namespace, group_namespace, group)

    allowed_users = document["identity"]["members"]
    task_map = _load_and_update_task_map(
        core,
        group_namespace,
        task_namespace,
        task,
        ksa,
        allowed_users,
    )

    oauth_client_id = _secret(platform_project, "jupyter-oauth-client-id")
    oauth_client_secret = _secret(platform_project, "jupyter-oauth-client-secret")
    tls_cert = _secret(platform_project, "jupyter-tls-cert")
    tls_key = _secret(platform_project, "jupyter-tls-key")

    tls_name = f"tls-{group}"
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
    listener_name = f"https-{group}"
    legacy_listener_name = f"https-{task}"
    listeners = [
        item for item in gateway["spec"].get("listeners", [])
        if item.get("name") not in {listener_name, legacy_listener_name}
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

    image_prefix = (
        f"{os.environ.get('REGION', 'asia-northeast3')}-docker.pkg.dev/"
        f"{platform_project}/ar-sbx-platform"
    )
    task_map_json = json.dumps(task_map, sort_keys=True)
    extra_config = f'''
import json

USER_TASK_MAP = json.loads({task_map_json!r})

def set_user_home(spawner):
    target = USER_TASK_MAP.get(spawner.user.name)
    if not target:
        raise RuntimeError(f"No task mapping for {{spawner.user.name}}")

    # Hub/Proxy are shared by group, but each user's notebook runs only
    # in the user's task namespace with the task-specific KSA/GSA chain.
    spawner.namespace = target["namespace"]
    spawner.service_account = target["ksa"]

    home = f"/home/{{spawner.user.name}}"
    spawner.environment["HOME"] = home
    spawner.environment["JUPYTERHUB_USER_HOME"] = home
    spawner.working_dir = home
    spawner.notebook_dir = home

    mounts = spawner.volume_mounts
    if isinstance(mounts, list):
        for mount in mounts:
            if isinstance(mount, dict) and mount.get("mountPath") == "/home/{{username}}":
                mount["mountPath"] = home
            elif isinstance(mount, dict) and mount.get("mount_path") == "/home/{{username}}":
                mount["mount_path"] = home
    elif isinstance(mounts, dict):
        for mount in mounts.values():
            if isinstance(mount, dict) and mount.get("mountPath") == "/home/{{username}}":
                mount["mountPath"] = home
            elif isinstance(mount, dict) and mount.get("mount_path") == "/home/{{username}}":
                mount["mount_path"] = home

c.Spawner.pre_spawn_hook = set_user_home
'''

    values = {
        "hub": {
            "image": {
                "name": f"{image_prefix}/jupyterhub-k8s-hub",
                "tag": "4.2.0",
            },
            "config": {
                "JupyterHub": {"authenticator_class": "google"},
                "Authenticator": {
                    "allow_all": False,
                    "allowed_users": sorted(task_map.keys()),
                },
                "GoogleOAuthenticator": {
                    "client_id": oauth_client_id,
                    "client_secret": oauth_client_secret,
                    "oauth_callback_url": f"https://{hostname}/hub/oauth_callback",
                    "hosted_domain": ["sonmap.net"],
                    "strip_domain": False,
                    "login_service": "Sonmap Google Account",
                },
                "KubeSpawner": {
                    "default_url": "/lab",
                },
            },
            "extraConfig": {
                "10-task-routing": extra_config,
            },
            "resources": {
                "requests": {"cpu": "250m", "memory": "512Mi"},
                "limits": {"cpu": "500m", "memory": "1Gi"},
            },
        },
        "proxy": {
            "service": {"type": "ClusterIP"},
            "chp": {
                "image": {
                    "name": f"{image_prefix}/jupyterhub-configurable-http-proxy",
                    "tag": "4.6.3",
                },
                "resources": {
                    "requests": {"cpu": "250m", "memory": "256Mi"},
                    "limits": {"cpu": "500m", "memory": "512Mi"},
                },
            },
        },
        "singleuser": {
            "image": {
                "name": f"{image_prefix}/jupyterhub-k8s-singleuser-standard",
                "tag": "4.2.0-r3",
            },
            "cpu": {"guarantee": 0.5, "limit": 0.5},
            "memory": {"guarantee": "1G", "limit": "1G"},
            "storage": {
                "type": "dynamic",
                "homeMountPath": "/home/{username}",
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
            "helm", "upgrade", "--install", f"jupyterhub-{group}",
            "jupyterhub/jupyterhub",
            "--version", "4.2.0",
            "--namespace", group_namespace,
            "--values", values_file.name,
            "--atomic", "--wait", "--timeout", "15m",
        ],
        child_env,
    )

    health_policy_name = f"jupyterhub-proxy-{group}"
    health_policy = {
        "apiVersion": "networking.gke.io/v1",
        "kind": "HealthCheckPolicy",
        "metadata": {"name": health_policy_name, "namespace": group_namespace},
        "spec": {
            "default": {
                "checkIntervalSec": 15,
                "timeoutSec": 5,
                "healthyThreshold": 1,
                "unhealthyThreshold": 2,
                "config": {
                    "type": "HTTP",
                    "httpHealthCheck": {
                        "portSpecification": "USE_SERVING_PORT",
                        "requestPath": "/_chp_healthz",
                    },
                },
            },
            "targetRef": {
                "group": "",
                "kind": "Service",
                "name": "proxy-public",
            },
        },
    }
    try:
        custom.get_namespaced_custom_object(
            "networking.gke.io",
            "v1",
            group_namespace,
            "healthcheckpolicies",
            health_policy_name,
        )
        custom.patch_namespaced_custom_object(
            "networking.gke.io",
            "v1",
            group_namespace,
            "healthcheckpolicies",
            health_policy_name,
            health_policy,
        )
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        custom.create_namespaced_custom_object(
            "networking.gke.io",
            "v1",
            group_namespace,
            "healthcheckpolicies",
            health_policy,
        )

    route_name = f"route-{group}"
    route = {
        "apiVersion": "gateway.networking.k8s.io/v1",
        "kind": "HTTPRoute",
        "metadata": {"name": route_name, "namespace": group_namespace},
        "spec": {
            "parentRefs": [{
                "name": "external-http-gateway",
                "namespace": "gateway-system",
                "sectionName": listener_name,
            }],
            "hostnames": [hostname],
            "rules": [{"backendRefs": [{"name": "proxy-public", "port": 80}]}],
        },
    }
    try:
        custom.get_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", group_namespace, "httproutes", route_name
        )
        custom.patch_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", group_namespace, "httproutes", route_name, route
        )
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        custom.create_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", group_namespace, "httproutes", route
        )

    # Remove temporary/legacy task-level web routing. The task namespace must
    # contain only task resources and spawned notebook pods, never Hub/Proxy.
    for policy in ["default-deny-ingress", "allow-gateway-to-test-web"]:
        if policy == "default-deny-ingress":
            continue
        try:
            networking.delete_namespaced_network_policy(policy, task_namespace)
        except client.ApiException as exc:
            if exc.status != 404:
                raise
    try:
        apps.delete_namespaced_deployment(f"web-{task}", task_namespace)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
    try:
        core.delete_namespaced_service(f"web-{task}", task_namespace)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
    try:
        custom.delete_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", task_namespace, "httproutes", f"route-{task}"
        )
    except client.ApiException as exc:
        if exc.status != 404:
            raise
    try:
        custom.delete_namespaced_custom_object(
            "networking.gke.io", "v1", task_namespace,
            "healthcheckpolicies", f"jupyterhub-proxy-{task}"
        )
    except client.ApiException as exc:
        if exc.status != 404:
            raise

    # Remove the legacy task-level JupyterHub release after the shared group
    # Hub/Proxy is healthy. Dynamic user PVCs are not Helm release objects.
    legacy_release = f"jupyterhub-{task}"
    if legacy_release != f"jupyterhub-{group}":
        _run(
            [
                "helm", "uninstall", legacy_release,
                "--namespace", task_namespace,
                "--ignore-not-found",
            ],
            child_env,
        )

    legacy_tls_name = f"tls-{task}"
    if legacy_tls_name != tls_name:
        try:
            core.delete_namespaced_secret(legacy_tls_name, "gateway-system")
        except client.ApiException as exc:
            if exc.status != 404:
                raise
