import hashlib
import json
import os
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException
from google.cloud import storage
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
    bucket = storage_client.bucket(parsed.netloc)
    blob = bucket.blob(parsed.path.lstrip("/"), generation=generation)
    return blob.download_as_bytes(if_generation_match=generation)


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.post("/provision")
def provision(req: ProvisionRequest) -> dict:
    allowed_bucket = os.environ.get("REQUEST_BUCKET")
    if allowed_bucket and not req.approved_json_uri.startswith(f"gs://{allowed_bucket}/approved/"):
        raise HTTPException(400, "approved_json_uri is outside the approved prefix")
    raw = read_generation(req.approved_json_uri, req.generation)
    if hashlib.sha256(raw).hexdigest() != req.sha256:
        raise HTTPException(400, "sha256 mismatch")
    document = json.loads(raw)
    if document.get("action") != "CREATE":
        raise HTTPException(400, "only CREATE is allowed")
    return {"accepted": True, "request_id": req.request_id, "task": document.get("task", {}).get("name")}
