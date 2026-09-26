import base64
import hashlib
import json
import os
import tempfile
import time
from urllib.parse import urlparse

import google.auth
from fastapi import FastAPI, HTTPException, Request
from google.auth import impersonated_credentials
from google.auth.transport.requests import AuthorizedSession, Request
from google.cloud import storage
from kubernetes import client
from pydantic import BaseModel, Field

app = FastAPI(title="EDP Sandbox Provisioner")
storage_client = storage.Client()


class ProvisionRequest(BaseModel):
    request_id: str = Field(pattern=r"^[A-Za-z0-9-]{3,80}$")
    approved_json_uri: str = Field(pattern=r"^gs://")
    generation: int
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


def read_generation(uri: str, generation: int) -> bytes:
    parsed = urlparse(uri)
    blob = storage_client.bucket(parsed.netloc).blob(
        parsed.path.lstrip("/"), generation=generation
    )
    return blob.download_as_bytes(if_generation_match=generation)


def require(document: dict, path: str):
    value = document
    for key in path.split("."):
        value = value.get(key) if isinstance(value, dict) else None
    if value in (None, "", []):
        raise HTTPException(400, f"missing required field: {path}")
    return value


def base_credentials():
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    return credentials


def im_blueprint(document: dict) -> dict:
    platform_project = os.environ["PLATFORM_PROJECT_ID"]
    region = os.environ.get("REGION", "asia-northeast3")
    task = require(document, "task.name")
    data_project = require(document, "project.project_id")
    repository = require(document, "source.repository")
    if not repository.startswith("https://"):
        repository = f"https://github.com/{repository}.git"
    values = {
        "platform_project_id": platform_project,
        "data_project_id": data_project,
        "create_project": str(bool(document["project"].get("create_project", False))).lower(),
        "project_name": document["project"].get("project_name", data_project),
        "folder_id": document["project"].get("folder_id", ""),
        "billing_account_id": document["project"].get("billing_account_id", ""),
        "region": region,
        "task_name": task,
        "group_email": require(document, "identity.group_email"),
        "dataset_id": require(document, "data.bigquery_dataset"),
        "bucket_name": require(document, "data.gcs_bucket"),
        "workload_identity_pool": f"{platform_project}.svc.id.goog",
    }
    return {
        "serviceAccount": (
            f"projects/{platform_project}/serviceAccounts/"
            f"{os.environ['IM_SERVICE_ACCOUNT']}"
        ),
        "terraformBlueprint": {
            "gitSource": {
                "repo": repository,
                "directory": "terraform/40-task/im",
                "ref": require(document, "source.commit_sha"),
            },
            "inputValues": values,
        },
        "labels": {"task": task.lower(), "managed-by": "sandbox-provisioner"},
    }


def wait_operation(session: AuthorizedSession, operation_name: str) -> None:
    url = f"https://config.googleapis.com/v1/{operation_name}"
    deadline = time.time() + 3300
    while time.time() < deadline:
        response = session.get(url, timeout=60)
        response.raise_for_status()
        operation = response.json()
        if operation.get("done"):
            if "error" in operation:
                raise RuntimeError(json.dumps(operation["error"]))
            return
        time.sleep(10)
    raise TimeoutError(f"Infrastructure Manager operation timed out: {operation_name}")


def apply_infrastructure_manager(document: dict) -> str:
    project = os.environ["PLATFORM_PROJECT_ID"]
    region = os.environ.get("REGION", "asia-northeast3")
    deployment_id = f"im-{require(document, 'task.name')}"
    deployment = f"projects/{project}/locations/{region}/deployments/{deployment_id}"
    session = AuthorizedSession(base_credentials())
    body = im_blueprint(document)
    create_url = (
        f"https://config.googleapis.com/v1/projects/{project}/locations/{region}/deployments"
        f"?deploymentId={deployment_id}"
    )
    response = session.post(create_url, json=body, timeout=60)
    if response.status_code == 409:
        body["name"] = deployment
        response = session.patch(
            f"https://config.googleapis.com/v1/{deployment}"
            "?updateMask=terraformBlueprint,serviceAccount,labels",
            json=body,
            timeout=60,
        )
    response.raise_for_status()
    wait_operation(session, response.json()["name"])
    return deployment


def kubernetes_api(document: dict):
    project = require(document, "gke.project_id")
    location = require(document, "gke.location")
    cluster_name = require(document, "gke.cluster_name")
    credentials = impersonated_credentials.Credentials(
        source_credentials=base_credentials(),
        target_principal=os.environ["GKE_ADMIN_SERVICE_ACCOUNT"],
        target_scopes=["https://www.googleapis.com/auth/cloud-platform"],
        lifetime=3600,
    )
    credentials.refresh(Request())
    session = AuthorizedSession(credentials)
    url = (
        f"https://container.googleapis.com/v1/projects/{project}/locations/{location}"
        f"/clusters/{cluster_name}"
    )
    response = session.get(url, timeout=60)
    response.raise_for_status()
    cluster = response.json()
    ca_file = tempfile.NamedTemporaryFile(delete=False)
    ca_file.write(base64.b64decode(cluster["masterAuth"]["clusterCaCertificate"]))
    ca_file.close()
    configuration = client.Configuration()
    configuration.host = f"https://{cluster['privateClusterConfig']['privateEndpoint']}"
    configuration.ssl_ca_cert = ca_file.name
    configuration.api_key = {"authorization": f"Bearer {credentials.token}"}
    return client.ApiClient(configuration)


def create_or_patch(read, create, patch, name: str, body):
    try:
        read(name)
        return patch(name, body)
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        return create(body)


def apply_gke(document: dict) -> None:
    api_client = kubernetes_api(document)
    core = client.CoreV1Api(api_client)
    apps = client.AppsV1Api(api_client)
    networking = client.NetworkingV1Api(api_client)
    custom = client.CustomObjectsApi(api_client)
    task = require(document, "task.namespace")
    gsa = f"gsa-jupyter-{task}@{require(document, 'project.project_id')}.iam.gserviceaccount.com"
    hostname = require(document, "gke.jupyter_domain")
    labels = {"app": "task-test-web", "task": task}
    create_or_patch(
        core.read_namespace,
        core.create_namespace,
        core.patch_namespace,
        task,
        client.V1Namespace(metadata=client.V1ObjectMeta(name=task)),
    )
    ksa_name = f"ksa-jupyter-{task}"
    ksa = client.V1ServiceAccount(
        metadata=client.V1ObjectMeta(
            name=ksa_name,
            namespace=task,
            annotations={"iam.gke.io/gcp-service-account": gsa},
        )
    )
    create_or_patch(
        lambda name: core.read_namespaced_service_account(name, task),
        lambda body: core.create_namespaced_service_account(task, body),
        lambda name, body: core.patch_namespaced_service_account(name, task, body),
        ksa_name,
        ksa,
    )
    quota_name = f"quota-{task}"
    quota = client.V1ResourceQuota(
        metadata=client.V1ObjectMeta(name=quota_name, namespace=task),
        spec=client.V1ResourceQuotaSpec(hard={
            "requests.cpu": "40",
            "requests.memory": "320Gi",
            "requests.storage": "3Ti",
            "persistentvolumeclaims": "100",
        }),
    )
    create_or_patch(
        lambda name: core.read_namespaced_resource_quota(name, task),
        lambda body: core.create_namespaced_resource_quota(task, body),
        lambda name, body: core.patch_namespaced_resource_quota(name, task, body),
        quota_name,
        quota,
    )
    deny_name = "default-deny-ingress"
    deny = client.V1NetworkPolicy(
        metadata=client.V1ObjectMeta(name=deny_name, namespace=task),
        spec=client.V1NetworkPolicySpec(
            pod_selector=client.V1LabelSelector(), policy_types=["Ingress"]
        ),
    )
    create_or_patch(
        lambda name: networking.read_namespaced_network_policy(name, task),
        lambda body: networking.create_namespaced_network_policy(task, body),
        lambda name, body: networking.patch_namespaced_network_policy(name, task, body),
        deny_name,
        deny,
    )
    deployment_name = f"web-{task}"
    deployment = client.V1Deployment(
        metadata=client.V1ObjectMeta(name=deployment_name, namespace=task),
        spec=client.V1DeploymentSpec(
            replicas=1,
            selector=client.V1LabelSelector(match_labels=labels),
            template=client.V1PodTemplateSpec(
                metadata=client.V1ObjectMeta(labels=labels),
                spec=client.V1PodSpec(
                    service_account_name=ksa_name,
                    containers=[client.V1Container(
                        name="hello-app",
                        image="us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0",
                        ports=[client.V1ContainerPort(container_port=8080, name="http")],
                        resources=client.V1ResourceRequirements(
                            requests={"cpu": "250m", "memory": "256Mi"},
                            limits={"cpu": "250m", "memory": "256Mi"},
                        ),
                    )],
                ),
            ),
        ),
    )
    create_or_patch(
        lambda name: apps.read_namespaced_deployment(name, task),
        lambda body: apps.create_namespaced_deployment(task, body),
        lambda name, body: apps.patch_namespaced_deployment(name, task, body),
        deployment_name,
        deployment,
    )
    service = client.V1Service(
        metadata=client.V1ObjectMeta(name=deployment_name, namespace=task),
        spec=client.V1ServiceSpec(
            selector=labels,
            ports=[client.V1ServicePort(name="http", port=80, target_port="http")],
        ),
    )
    create_or_patch(
        lambda name: core.read_namespaced_service(name, task),
        lambda body: core.create_namespaced_service(task, body),
        lambda name, body: core.patch_namespaced_service(name, task, body),
        deployment_name,
        service,
    )
    allow_name = "allow-gateway-to-test-web"
    allow = client.V1NetworkPolicy(
        metadata=client.V1ObjectMeta(name=allow_name, namespace=task),
        spec=client.V1NetworkPolicySpec(
            pod_selector=client.V1LabelSelector(match_labels=labels),
            ingress=[client.V1NetworkPolicyIngressRule()],
            policy_types=["Ingress"],
        ),
    )
    create_or_patch(
        lambda name: networking.read_namespaced_network_policy(name, task),
        lambda body: networking.create_namespaced_network_policy(task, body),
        lambda name, body: networking.patch_namespaced_network_policy(name, task, body),
        allow_name,
        allow,
    )
    route_name = f"route-{task}"
    route = {
        "apiVersion": "gateway.networking.k8s.io/v1",
        "kind": "HTTPRoute",
        "metadata": {"name": route_name, "namespace": task},
        "spec": {
            "parentRefs": [{
                "name": "external-http-gateway",
                "namespace": "gateway-system",
                "sectionName": "http",
            }],
            "hostnames": [hostname],
            "rules": [{"backendRefs": [{"name": deployment_name, "port": 80}]}],
        },
    }
    try:
        custom.get_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", task, "httproutes", route_name
        )
        custom.patch_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", task, "httproutes", route_name, route
        )
    except client.ApiException as exc:
        if exc.status != 404:
            raise
        custom.create_namespaced_custom_object(
            "gateway.networking.k8s.io", "v1", task, "httproutes", route
        )


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.post("/provision")
def provision(req: ProvisionRequest) -> dict:
    allowed_bucket = os.environ.get("REQUEST_BUCKET")
    if allowed_bucket and not req.approved_json_uri.startswith(
        f"gs://{allowed_bucket}/approved/"
    ):
        raise HTTPException(400, "approved_json_uri is outside the approved prefix")
    raw = read_generation(req.approved_json_uri, req.generation)
    if hashlib.sha256(raw).hexdigest() != req.sha256:
        raise HTTPException(400, "sha256 mismatch")
    document = json.loads(raw)
    if document.get("action") != "CREATE":
        raise HTTPException(400, "only CREATE is allowed")
    try:
        deployment = apply_infrastructure_manager(document)
        apply_gke(document)
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc
    return {
        "accepted": True,
        "request_id": req.request_id,
        "task": document["task"]["name"],
        "deployment": deployment,
        "gke_applied": True,
    }


@app.post("/events/storage")
async def storage_event(request: Request) -> dict:
    envelope = await request.json()
    event = envelope.get("data", envelope)
    bucket = event.get("bucket")
    name = event.get("name")
    generation = int(event.get("generation", 0))
    allowed_bucket = os.environ.get("REQUEST_BUCKET")
    if bucket != allowed_bucket or not name or not name.startswith("approved/"):
        return {"ignored": True}
    raw = read_generation(f"gs://{bucket}/{name}", generation)
    document = json.loads(raw)
    if document.get("action") != "CREATE":
        raise HTTPException(400, "only CREATE is allowed")
    try:
        deployment = apply_infrastructure_manager(document)
        apply_gke(document)
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc
    return {
        "accepted": True,
        "request_id": document.get("request_id"),
        "task": document["task"]["name"],
        "deployment": deployment,
        "gke_applied": True,
    }
