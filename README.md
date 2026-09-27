# GCP EDP Sandbox Platform - 4th Terraform Test

GKE Autopilot 기반 Sandbox 플랫폼을 Terraform, Infrastructure Manager, Cloud Build, Cloud Run Provisioner, Artifact Registry로 자동 구축하는 프로젝트입니다.

> 상세 구성도 및 실제 실행 흐름: **[docs/architecture-and-flow.md](docs/architecture-and-flow.md)**  
> IAM/실행 경계 상세: **[docs/execution-and-iam.md](docs/execution-and-iam.md)**

## 프로젝트 역할

| 프로젝트 | 역할 |
|---|---|
| `gcp-prod-edp-hub-vpchost` | Shared VPC Host, Subnet, NAT, ALB/Gateway 네트워크 |
| `gcp-sbx-edp-gke01` | GKE Autopilot, Cloud Run, Cloud Build, Artifact Registry, Infrastructure Manager, Eventarc |
| `gcp-sbx-edp-comn-509423` | task01 BigQuery/GCS/Jupyter GSA 등 Task 자원 |
| `pjt-c-admin` | 메인 Data Lake / BigQuery 원천 데이터 |

## 신규 구축 순서

**00 → 10 → 21 → 20 → 30 → 40**

```mermaid
flowchart LR
    S00["00 Bootstrap<br/>Project: gcp-sbx-edp-gke01"]
      -->|"①"| S10["10 Network<br/>Host: gcp-prod-edp-hub-vpchost"]

    S10 -->|"②"| S21["21 Enable APIs<br/>gcp-sbx-edp-gke01<br/>+ pjt-c-admin"]

    S21 -->|"③"| S20["20 Admin IAM<br/>Project: gcp-sbx-edp-gke01"]

    S20 -->|"④"| S30["30 Foundation<br/>Infrastructure Manager<br/>+ Cloud Build"]

    S30 -->|"⑤"| S40["40 Task Automation<br/>Approved JSON → IM → GKE"]
```

## 실행 경계

| 순서 | Root | 실행 위치 | 인증 | 방식 |
|---:|---|---|---|---|
| 00 | `terraform/00-bootstrap` | `infra-son01` | `admin@sonmap.net` | 수동 Terraform |
| 10 | `terraform/10-network-host` | `infra-son01` | `admin@sonmap.net` | 수동 Terraform |
| 21 | `terraform/21-enable-apis` | `infra-son01` | `admin@sonmap.net` | Platform/Data API 활성화 |
| 20 | `terraform/20-admin-iam` | `infra-son01` | `admin@sonmap.net` | Service Account/IAM 구성 |
| 30 | `terraform/30-foundation` | `infra-son01`에서 요청 | VM SA → `sa-im-foundation` | Infrastructure Manager → 내부 Cloud Build → Terraform |
| 40 | `terraform/40-task/im` + Python | 자동화 | 단계별 전용 SA | Approved JSON → Eventarc → Cloud Run → IM → GKE |

VM 기본 서비스 계정은 `620081195575-compute@developer.gserviceaccount.com`입니다.

---

# 30 Foundation - 실제 흐름

30단계는 `terraform/30-foundation`을 Infrastructure Manager에 전달하고, Infrastructure Manager가 내부 Cloud Build 실행환경에서 Terraform을 수행합니다.

Cloud Run Provisioner는 별도 Cloud Build로 Docker 이미지를 생성하여 Artifact Registry에 Push한 뒤 30단계 자동화 자원에서 사용합니다.

```mermaid
flowchart TB
    GIT["① GitHub<br/>terraform/30-foundation"]
    IM["② Infrastructure Manager<br/>gcp-sbx-edp-gke01"]
    CBIM["③ IM 내부 Cloud Build"]
    TF["④ Terraform Apply"]

    GKE["⑤ GKE Autopilot<br/>gcp-sbx-edp-gke01"]
    AR["⑥ Artifact Registry<br/>ar-sbx-platform"]
    REQ["⑦ Request Bucket<br/>gcp-sbx-edp-gke01-requests"]
    BUNDLE["⑧ Bundle Bucket<br/>gcp-sbx-edp-gke01-bundles"]

    SRC["⑨ Python Provisioner Source<br/>main.py + jupyterhub.py"]
    GCSBUILD["⑩ Cloud Build Source<br/>gs://...-bundles/cloudbuild/source"]
    CBBUILD["⑪ Cloud Build<br/>Docker Build"]
    IMAGE["⑫ Artifact Registry<br/>sandbox-provisioner:latest"]

    IM2["⑬ 30-foundation 재적용"]
    CBIM2["⑭ IM 내부 Cloud Build"]
    RUN["⑮ Cloud Run<br/>run-sbx-provisioner"]
    EVENT["⑯ Eventarc Trigger"]

    GIT -->|"①"| IM
    IM -->|"②"| CBIM
    CBIM -->|"③"| TF
    TF -->|"④"| GKE
    TF -->|"⑤"| AR
    TF -->|"⑥"| REQ
    TF -->|"⑦"| BUNDLE

    SRC -->|"⑧ Source Stage"| GCSBUILD
    GCSBUILD -->|"⑨ Build"| CBBUILD
    CBBUILD -->|"⑩ Push"| IMAGE

    IMAGE -->|"⑪"| IM2
    IM2 -->|"⑫"| CBIM2
    CBIM2 -->|"⑬"| RUN
    CBIM2 -->|"⑭"| EVENT

    classDef python fill:#f8cecc,stroke:#b85450,stroke-width:3px;
    classDef terraform fill:#d5e8d4,stroke:#82b366,stroke-width:2px;
    classDef cloudbuild fill:#fff2cc,stroke:#d6b656,stroke-width:2px;
    classDef gcp fill:#dae8fc,stroke:#6c8ebf;

    class SRC,RUN python;
    class TF terraform;
    class CBIM,CBBUILD,CBIM2 cloudbuild;
    class IM,IM2,GKE,AR,REQ,BUNDLE,EVENT gcp;
```

---

# Artifact Registry - Build / Push 구조

현재 `ar-sbx-platform`에는 주요 이미지 5개가 있으며, Cloud Build 작업은 대략 3종류로 분리됩니다.

```mermaid
flowchart TB
    GIT["GitHub Repository"]

    GIT -->|"①"| B1["Cloud Build #1<br/>build-provisioner.yaml"]
    B1 -->|"② Build / Push"| I1["sandbox-provisioner"]

    GIT -->|"③"| B2["Cloud Build #2<br/>build-jupyter-singleuser.yaml"]
    B2 -->|"④ Build / Push"| I2["jupyterhub-k8s-singleuser-standard"]

    GIT -->|"⑤"| B3["Cloud Build #3<br/>mirror-jupyterhub-images.yaml"]
    B3 -->|"⑥"| I3["jupyterhub-k8s-hub"]
    B3 -->|"⑦"| I4["jupyterhub-configurable-http-proxy"]
    B3 -->|"⑧"| I5["jupyterhub-k8s-singleuser-sample"]

    I1 --> AR["Artifact Registry<br/>ar-sbx-platform<br/>gcp-sbx-edp-gke01"]
    I2 --> AR
    I3 --> AR
    I4 --> AR
    I5 --> AR

    classDef build fill:#fff2cc,stroke:#d6b656,stroke-width:2px;
    classDef image fill:#f8cecc,stroke:#b85450;
    classDef registry fill:#d5e8d4,stroke:#82b366,stroke-width:2px;

    class B1,B2,B3 build;
    class I1,I2,I3,I4,I5 image;
    class AR registry;
```

| 이미지 | 용도 |
|---|---|
| `sandbox-provisioner` | Cloud Run Python 자동화 |
| `jupyterhub-k8s-hub` | JupyterHub Hub Pod |
| `jupyterhub-configurable-http-proxy` | JupyterHub Proxy Pod |
| `jupyterhub-k8s-singleuser-standard` | 실제 사용자 Notebook Pod |
| `jupyterhub-k8s-singleuser-sample` | 테스트/샘플 이미지 |

---

# 40 Task - 실제 자동 처리 흐름

40단계의 실제 시작점은 Approved JSON입니다.

예:

```text
gs://gcp-sbx-edp-gke01-requests/approved/task01-jupyterhub1.json
```

Eventarc가 Cloud Run `run-sbx-provisioner`를 호출하고, Python `main.py`가 Infrastructure Manager 작업을 생성합니다. IM 내부 Cloud Build/Terraform이 완료된 후 Python이 다시 진행되어 GKE Private Endpoint에 접속하고 `jupyterhub.py`가 Helm으로 JupyterHub를 배포합니다.

```mermaid
flowchart TB
    JSON["① Approved JSON<br/>task01-jupyterhub1.json"]
    GCS["② Request Bucket<br/>gs://gcp-sbx-edp-gke01-requests/approved/"]
    EVENT["③ Eventarc<br/>gcp-sbx-edp-gke01"]

    MAIN["④ Python main.py<br/>storage_event()"]
    READ["⑤ Python main.py<br/>JSON Download / 검증"]
    IMCALL["⑥ Python main.py<br/>apply_infrastructure_manager()"]

    IM["⑦ Infrastructure Manager<br/>im-task01"]
    CB["⑧ IM 내부 Cloud Build"]
    TF["⑨ Terraform<br/>terraform/40-task/im"]

    TASK["⑩ Project / IAM / BigQuery / GCS / GSA<br/>gcp-sbx-edp-comn-509423<br/>+ pjt-c-admin"]

    WAIT["⑪ Python main.py<br/>IM 완료 후 계속 수행"]
    GKEAPI["⑫ Python apply_gke()<br/>Private GKE API"]
    K8S["⑬ Namespace / KSA / Quota / Policy / Service"]
    JH["⑭ Python jupyterhub.py<br/>apply_jupyterhub()"]
    HELM["⑮ Python subprocess<br/>helm upgrade --install<br/>jupyterhub-task01"]
    HUB["⑯ GKE JupyterHub<br/>hub + proxy"]
    USER["⑰ User Notebook Pod<br/>jupyter-user01..."]
    ROUTE["⑱ HTTPS Listener / HTTPRoute<br/>GKE Gateway / ALB"]

    JSON -->|"① Upload"| GCS
    GCS -->|"② Object Finalized"| EVENT
    EVENT -->|"③ HTTP"| MAIN
    MAIN -->|"④"| READ
    READ -->|"⑤"| IMCALL
    IMCALL -->|"⑥"| IM
    IM -->|"⑦"| CB
    CB -->|"⑧"| TF
    TF -->|"⑨"| TASK
    TASK -->|"⑩ IM 완료"| WAIT
    WAIT -->|"⑪"| GKEAPI
    GKEAPI -->|"⑫"| K8S
    K8S -->|"⑬"| JH
    JH -->|"⑭"| HELM
    HELM -->|"⑮"| HUB
    HUB -->|"⑯ Spawn"| USER
    HELM -->|"⑰"| ROUTE

    classDef python fill:#f8cecc,stroke:#b85450,stroke-width:3px;
    classDef terraform fill:#d5e8d4,stroke:#82b366,stroke-width:2px;
    classDef cloudbuild fill:#fff2cc,stroke:#d6b656,stroke-width:2px;
    classDef gcp fill:#dae8fc,stroke:#6c8ebf;
    classDef runtime fill:#e1d5e7,stroke:#9673a6;

    class MAIN,READ,IMCALL,WAIT,GKEAPI,JH,HELM python;
    class TF terraform;
    class CB cloudbuild;
    class GCS,EVENT,IM,TASK,ROUTE gcp;
    class K8S,HUB,USER runtime;
```

### 색상 의미

| 색상 | 의미 |
|---|---|
| 빨강 | Python (`main.py`, `jupyterhub.py`) 수행 영역 |
| 녹색 | Terraform 수행 |
| 노랑 | Cloud Build 수행 |
| 파랑 | GCP 관리 자원 |
| 보라 | GKE/Jupyter Runtime |

---

## 디렉터리

```text
terraform/
├── 00-bootstrap/
├── 10-network-host/
├── 20-admin-iam/
├── 21-enable-apis/
├── 30-foundation/
└── 40-task/
    ├── 10-project/
    ├── 15-cloud-identity/
    ├── 20-project-iam/
    ├── 30-data/
    ├── 40-gke/
    ├── 50-loadbalancer/
    └── im/

cloudbuild/
├── build-provisioner.yaml
├── build-jupyter-singleuser.yaml
├── mirror-jupyterhub-images.yaml
└── sandbox-orchestrate.yaml

cloudrun-provisioner/
├── Dockerfile
├── main.py
├── jupyterhub.py
└── requirements.txt

docs/
├── architecture-and-flow.md
└── execution-and-iam.md
```

## 변수 파일 사용

| 단계 | Git 예제 파일 | 실제 실행 파일 |
|---:|---|---|
| 00 | `terraform.tfvars.example` | `terraform.tfvars` |
| 10 | `terraform.tfvars.example` | `terraform.tfvars` |
| 20 | `terraform.tfvars.example` | `terraform.tfvars` |
| 30 | `terraform.auto.tfvars.json.example` | IM Bundle의 `terraform.auto.tfvars.json` |
| 40 | Root별 예제 | Approved JSON에서 자동 생성/전달 |

## 안전 원칙

- Host Project API는 별도 스크립트로 필요한 항목만 활성화합니다.
- 21단계에서 Google 관리 Service Identity를 먼저 생성한 후 20단계 IAM을 적용합니다.
- 30 이후 사용자 ADC 및 `GOOGLE_OAUTH_ACCESS_TOKEN` 의존을 제거합니다.
- Infrastructure Manager Source는 승인된 commit SHA를 사용합니다.
- Terraform State, Plan, 인증키, 로컬 `terraform.tfvars`는 Git에 저장하지 않습니다.
- `gke-gmp-system`, `gke-managed-cim`, `kube-system`은 Autopilot 시스템 영역이므로 업무 Pod 중단 목적으로 삭제하지 않습니다.

## 상세 문서

- [Architecture & Execution Flow](docs/architecture-and-flow.md)
- [Execution and IAM](docs/execution-and-iam.md)
- [30 Foundation README](terraform/30-foundation/README.md)
- [40 Task README](terraform/40-task/README.md)
