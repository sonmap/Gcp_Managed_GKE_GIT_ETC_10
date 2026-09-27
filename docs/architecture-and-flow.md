# GCP EDP Sandbox Platform - Architecture & Execution Flow

이 문서는 `Gcp_Managed_GKE_GIT_ETC_10`의 실제 실행 구조를 기준으로 00 → 10 → 21 → 20 → 30 → 40 단계와 Cloud Build, Infrastructure Manager, Artifact Registry, Cloud Run Python Provisioner, GKE/JupyterHub의 관계를 정리합니다.

> 신규 구축 순서: **00 → 10 → 21 → 20 → 30 → 40**

## 1. 프로젝트 역할

| 프로젝트 | 역할 |
|---|---|
| `gcp-prod-edp-hub-vpchost` | Shared VPC Host, Subnet, NAT, ALB/Gateway 네트워크 |
| `gcp-sbx-edp-gke01` | GKE Autopilot, Cloud Run, Cloud Build, Artifact Registry, Infrastructure Manager, Eventarc, Request/Bundle Bucket |
| `gcp-sbx-edp-comn-509423` | task01 BigQuery/GCS/Jupyter GSA 등 Task 데이터 자원 |
| `pjt-c-admin` | 메인 Data Lake / BigQuery 원천 데이터 |

## 2. 전체 단계 흐름

```mermaid
flowchart LR
    S00["00 Bootstrap<br/>Project: gcp-sbx-edp-gke01"]
      -->|"①"| S10["10 Network<br/>Host: gcp-prod-edp-hub-vpchost"]

    S10 -->|"②"| S21["21 Enable APIs<br/>Platform: gcp-sbx-edp-gke01<br/>Data: pjt-c-admin"]

    S21 -->|"③"| S20["20 Admin IAM<br/>Project: gcp-sbx-edp-gke01"]

    S20 -->|"④"| S30["30 Foundation<br/>IM + Cloud Build<br/>Project: gcp-sbx-edp-gke01"]

    S30 -->|"⑤"| S40["40 Task Automation<br/>Task: gcp-sbx-edp-comn-509423<br/>GKE: gcp-sbx-edp-gke01"]
```

---

## 3. 00-bootstrap

Terraform 원격 State와 최소 Bootstrap API를 준비합니다.

```mermaid
flowchart LR
    A["infra-son01<br/>Project: gcp-sbx-edp-gke01"]
      -->|"① Terraform 실행"| B["00-bootstrap"]

    B -->|"② API 활성화"| C["Resource Manager / IAM / Service Usage<br/>Infrastructure Manager / Storage"]
    B -->|"③ 생성"| D["Terraform State Bucket<br/>Project: gcp-sbx-edp-gke01"]
    E["VM Service Account"] -->|"④ State 접근권한"| D
```

---

## 4. 10-network-host

Shared VPC와 Platform 서비스가 사용할 공통 네트워크를 구성합니다.

```mermaid
flowchart TB
    H["Host Project<br/>gcp-prod-edp-hub-vpchost"]
      -->|"①"| VPC["Shared VPC<br/>vpc-prod-edp-hub"]

    VPC -->|"②"| ADM["Admin Subnet"]
    VPC -->|"③"| INFRA["Infra Admin Subnet"]
    VPC -->|"④"| ALBF["ALB Frontend Subnet"]
    VPC -->|"⑤"| ALBP["ALB Proxy Subnet"]
    VPC -->|"⑥"| GKE["GKE Subnet + Pod Secondary Range"]
    VPC -->|"⑦"| RUN["Cloud Run Subnet"]
    VPC -->|"⑧"| PSA["Cloud Build PSA"]

    INFRA -->|"⑨"| NAT["Cloud Router + NAT"]
    VPC -->|"⑩ Shared VPC 연결"| SP["Service Project<br/>gcp-sbx-edp-gke01"]
```

---

## 5. 21-enable-apis

서비스 계정 및 Google 관리 Service Agent가 정상 생성될 수 있도록 Platform/Data API를 활성화합니다.

```mermaid
flowchart TB
    A["21-enable-apis"]
      -->|"①"| P["Platform Project<br/>gcp-sbx-edp-gke01"]

    P -->|"②"| GKE["GKE API"]
    P -->|"③"| RUN["Cloud Run API"]
    P -->|"④"| CB["Cloud Build API"]
    P -->|"⑤"| AR["Artifact Registry API"]
    P -->|"⑥"| IM["Infrastructure Manager API"]
    P -->|"⑦"| EA["Eventarc API"]
    P -->|"⑧"| WF["Workflows API"]

    A -->|"⑨"| D["Data Project<br/>pjt-c-admin"]
    D -->|"⑩"| BQ["BigQuery API"]
    D -->|"⑪"| BQS["BigQuery Storage API"]
    D -->|"⑫"| GCS["Cloud Storage API"]
```

---

## 6. 20-admin-iam

Automation Service Account와 단계별 권한을 분리합니다.

```mermaid
flowchart TB
    VM["infra-son01 VM SA<br/>Project: gcp-sbx-edp-gke01"]

    VM -->|"① Impersonate"| FND["sa-im-foundation"]
    VM -->|"② Impersonate"| PF["sa-im-project-factory"]
    VM -->|"③ Impersonate"| PIAM["sa-im-project-iam"]
    VM -->|"④ Impersonate"| DATA["sa-im-data-admin"]
    VM -->|"⑤ Impersonate"| GKEA["sa-im-gke-admin"]
    VM -->|"⑥ Impersonate"| LB["sa-im-lb-admin"]

    FND -->|"⑦"| PLATFORM["Platform Resources<br/>gcp-sbx-edp-gke01"]
    DATA -->|"⑧"| DATAP["Data Resources<br/>pjt-c-admin / Task Project"]
    GKEA -->|"⑨"| GKE["GKE Cluster<br/>gcp-sbx-edp-gke01"]
    LB -->|"⑩"| NET["ALB / Shared VPC<br/>gcp-prod-edp-hub-vpchost"]
```

---

# 7. 30-foundation - 실제 실행 순서

30단계는 GitHub의 `terraform/30-foundation`을 Infrastructure Manager에 전달하고, Infrastructure Manager가 내부 Cloud Build 실행환경을 사용하여 Terraform을 수행합니다.

30단계 후반에는 Cloud Run Provisioner 이미지를 별도로 Cloud Build하여 Artifact Registry에 Push한 뒤, 해당 이미지를 사용하도록 30-foundation을 다시 적용하여 Cloud Run/Eventarc 자동화 자원을 완성합니다.

```mermaid
flowchart TB
    GIT["① GitHub Source<br/>terraform/30-foundation"]
    IM["② Infrastructure Manager<br/>Project: gcp-sbx-edp-gke01"]
    CBIM["③ IM 내부 Cloud Build<br/>Terraform Runtime"]
    TF["④ Terraform init / validate / apply"]

    GKE["⑤ GKE Autopilot<br/>gke-sbx-edp-main-an3"]
    AR["⑥ Artifact Registry<br/>ar-sbx-platform"]
    REQ["⑦ Request Bucket<br/>gcp-sbx-edp-gke01-requests"]
    BUNDLE["⑧ Bundle Bucket<br/>gcp-sbx-edp-gke01-bundles"]

    SRC["⑨ cloudrun-provisioner Source<br/>Dockerfile + main.py + jupyterhub.py"]
    GCSBUILD["⑩ Build Source Staging<br/>gs://gcp-sbx-edp-gke01-bundles/cloudbuild/source"]
    CBBUILD["⑪ Cloud Build<br/>build-provisioner.yaml"]
    IMAGE["⑫ Artifact Registry Image<br/>sandbox-provisioner:latest"]

    IM2["⑬ Infrastructure Manager 재적용"]
    CBIM2["⑭ IM 내부 Cloud Build"]
    RUN["⑮ Cloud Run<br/>run-sbx-provisioner"]
    EVENT["⑯ Eventarc Trigger<br/>approved/*.json"]
    GW["⑰ GKE Gateway / 공통 진입점"]

    GIT -->|"① Source 지정"| IM
    IM -->|"② Deployment"| CBIM
    CBIM -->|"③ Terraform 실행"| TF

    TF -->|"④"| GKE
    TF -->|"⑤"| AR
    TF -->|"⑥"| REQ
    TF -->|"⑦"| BUNDLE

    SRC -->|"⑧ Source Stage"| GCSBUILD
    GCSBUILD -->|"⑨ Build Submit"| CBBUILD
    CBBUILD -->|"⑩ Docker Build + Push"| IMAGE

    IMAGE -->|"⑪ Image 준비"| IM2
    IM2 -->|"⑫ Update"| CBIM2
    CBIM2 -->|"⑬ Terraform Apply"| RUN
    CBIM2 -->|"⑭ Terraform Apply"| EVENT
    GKE -->|"⑮"| GW

    classDef python fill:#f8cecc,stroke:#b85450,stroke-width:3px;
    classDef terraform fill:#d5e8d4,stroke:#82b366,stroke-width:2px;
    classDef cloudbuild fill:#fff2cc,stroke:#d6b656,stroke-width:2px;
    classDef gcp fill:#dae8fc,stroke:#6c8ebf;

    class SRC,RUN python;
    class TF terraform;
    class CBIM,CBBUILD,CBIM2 cloudbuild;
    class IM,IM2,GKE,AR,REQ,BUNDLE,EVENT,GW gcp;
```

## 7.1 30단계 색상 의미

| 색상 | 의미 |
|---|---|
| 빨강 | Python/Provisioner 관련 영역 |
| 녹색 | Terraform 수행 |
| 노랑 | Cloud Build 수행 |
| 파랑 | GCP 관리 자원 |

---

# 8. Artifact Registry 이미지 Build / Push 구조

`ar-sbx-platform`에는 현재 주요 이미지가 5개 있으며, 이미지 5개가 Cloud Build 5개를 의미하지는 않습니다. 현재 저장소에서는 대략 3종류의 Build/Mirror 작업으로 구성됩니다.

| Cloud Build 정의 | 결과 이미지 |
|---|---|
| `cloudbuild/build-provisioner.yaml` | `sandbox-provisioner` |
| `cloudbuild/build-jupyter-singleuser.yaml` | `jupyterhub-k8s-singleuser-standard` |
| `cloudbuild/mirror-jupyterhub-images.yaml` | `jupyterhub-k8s-hub`, `jupyterhub-configurable-http-proxy`, `jupyterhub-k8s-singleuser-sample` |

```mermaid
flowchart TB
    GIT["GitHub Repository<br/>Gcp_Managed_GKE_GIT_ETC_10"]

    GIT -->|"①"| B1["Cloud Build #1<br/>build-provisioner.yaml"]
    B1 -->|"② Build / Push"| I1["sandbox-provisioner"]

    GIT -->|"③"| B2["Cloud Build #2<br/>build-jupyter-singleuser.yaml"]
    B2 -->|"④ Build / Push"| I2["jupyterhub-k8s-singleuser-standard"]

    GIT -->|"⑤"| B3["Cloud Build #3<br/>mirror-jupyterhub-images.yaml"]
    B3 -->|"⑥ Mirror / Push"| I3["jupyterhub-k8s-hub"]
    B3 -->|"⑦ Mirror / Push"| I4["jupyterhub-configurable-http-proxy"]
    B3 -->|"⑧ Mirror / Push"| I5["jupyterhub-k8s-singleuser-sample"]

    I1 --> AR["Artifact Registry<br/>ar-sbx-platform<br/>Project: gcp-sbx-edp-gke01"]
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

---

# 9. 40-task - 실제 실행 순서

40단계는 먼저 Provisioner 이미지가 준비되어 있어야 합니다. 이후 승인 JSON을 `gcp-sbx-edp-gke01-requests/approved/`에 업로드하면 Eventarc가 Cloud Run Python Provisioner를 호출합니다.

Cloud Run의 `main.py`가 Infrastructure Manager를 호출하고, IM 작업이 끝난 뒤 동일 Python 프로세스가 GKE Private Endpoint에 접속하여 Namespace/KSA/Quota 등을 적용하고, `jupyterhub.py`가 Helm을 실행하여 JupyterHub를 배포합니다.

```mermaid
flowchart TB
    JSON["① 승인 JSON<br/>task01-jupyterhub1.json"]
    GCS["② Request Bucket<br/>gs://gcp-sbx-edp-gke01-requests/<br/>approved/task01-jupyterhub1.json"]
    EVENT["③ Eventarc<br/>Project: gcp-sbx-edp-gke01"]

    subgraph PY1["Python 수행영역 ① - Cloud Run run-sbx-provisioner"]
        MAIN1["④ main.py<br/>storage_event()"]
        READ["⑤ main.py<br/>GCS JSON Download / 검증"]
        IMCALL["⑥ main.py<br/>apply_infrastructure_manager()"]
        WAIT["⑩ main.py<br/>wait_operation()"]
    end

    IM["⑦ Infrastructure Manager<br/>im-task01<br/>Project: gcp-sbx-edp-gke01"]
    CB["⑧ IM 내부 Cloud Build<br/>Terraform Runtime"]
    TF["⑨ Terraform Apply<br/>terraform/40-task/im"]

    TASK["Task Project / IAM<br/>gcp-sbx-edp-comn-509423"]
    DATA["BigQuery / GCS / Jupyter GSA<br/>gcp-sbx-edp-comn-509423 + pjt-c-admin"]

    subgraph PY2["Python 수행영역 ② - Cloud Run run-sbx-provisioner"]
        GKEFUNC["⑪ main.py<br/>apply_gke()"]
        GKEAPI["⑫ Private GKE API 연결"]
        K8S["⑬ Python Kubernetes Client<br/>Namespace / KSA / Quota / Policy / Service"]
        JFUNC["⑭ jupyterhub.py<br/>apply_jupyterhub()"]
        SECRET["⑮ Secret Manager 조회<br/>OAuth / TLS"]
        HELM["⑯ Python subprocess<br/>helm upgrade --install<br/>jupyterhub-task01"]
        ROUTE["⑰ Kubernetes API<br/>HTTPS Listener / HealthCheckPolicy / HTTPRoute"]
    end

    HUB["⑱ JupyterHub<br/>hub + proxy<br/>Namespace: task01"]
    USER["⑲ User Login / Spawn<br/>jupyter-user01..."]
    GW["⑳ GKE Gateway / ALB<br/>GKE: gcp-sbx-edp-gke01<br/>Network: gcp-prod-edp-hub-vpchost"]

    JSON -->|"① Upload"| GCS
    GCS -->|"② Object Finalized"| EVENT
    EVENT -->|"③ HTTP 호출"| MAIN1
    MAIN1 -->|"④"| READ
    READ -->|"⑤"| IMCALL

    IMCALL -->|"⑥ Deployment API"| IM
    IM -->|"⑦ Cloud Build 생성"| CB
    CB -->|"⑧ Terraform"| TF
    TF -->|"⑨"| TASK
    TF -->|"⑨"| DATA
    TF -->|"⑩ 완료"| WAIT

    WAIT -->|"⑪ Python 처리 재개"| GKEFUNC
    GKEFUNC -->|"⑫"| GKEAPI
    GKEAPI -->|"⑬"| K8S
    K8S -->|"⑭"| JFUNC
    JFUNC -->|"⑮"| SECRET
    SECRET -->|"⑯"| HELM

    HELM -->|"⑰ 생성"| HUB
    HELM -->|"⑱ Route 구성"| ROUTE
    HUB -->|"⑲ 로그인 후 Spawn"| USER
    ROUTE -->|"⑳"| GW

    classDef python fill:#f8cecc,stroke:#b85450,stroke-width:3px;
    classDef terraform fill:#d5e8d4,stroke:#82b366,stroke-width:2px;
    classDef cloudbuild fill:#fff2cc,stroke:#d6b656,stroke-width:2px;
    classDef gcp fill:#dae8fc,stroke:#6c8ebf;
    classDef runtime fill:#e1d5e7,stroke:#9673a6;

    class MAIN1,READ,IMCALL,WAIT,GKEFUNC,GKEAPI,K8S,JFUNC,SECRET,HELM,ROUTE python;
    class TF terraform;
    class CB cloudbuild;
    class IM,GCS,EVENT,TASK,DATA,GW gcp;
    class HUB,USER runtime;
```

## 9.1 40단계 핵심 실행 순서

```text
승인 JSON
  ↓
Request Bucket approved/
  ↓
Eventarc
  ↓
Cloud Run Provisioner
  ↓
Python main.py
  ↓
Infrastructure Manager
  ↓
IM 내부 Cloud Build
  ↓
Terraform 40-task/im
  ↓
Task Project / IAM / BigQuery / GCS / Jupyter GSA
  ↓
Python main.py 재개
  ↓
Private GKE API
  ↓
Namespace / KSA / Quota / NetworkPolicy
  ↓
Python jupyterhub.py
  ↓
Helm upgrade --install
  ↓
Hub / Proxy
  ↓
User Jupyter Pod
```

---

# 10. Artifact Registry Image 사용처

| 이미지 | 용도 | 실행 위치 |
|---|---|---|
| `sandbox-provisioner` | 승인 JSON 처리, IM 호출, GKE/JupyterHub 자동화 | Cloud Run |
| `jupyterhub-k8s-hub` | JupyterHub 중앙 Hub | GKE `hub` Pod |
| `jupyterhub-configurable-http-proxy` | 사용자 요청 Proxy | GKE `proxy` Pod |
| `jupyterhub-k8s-singleuser-standard` | 표준 사용자 Notebook | GKE `jupyter-user...` Pod |
| `jupyterhub-k8s-singleuser-sample` | 테스트/샘플 Notebook 이미지 | GKE 테스트 용도 |

```mermaid
flowchart TB
    AR["Artifact Registry<br/>ar-sbx-platform"]

    AR -->|"① Pull"| PROV["sandbox-provisioner"]
    PROV -->|"②"| RUN["Cloud Run<br/>run-sbx-provisioner"]

    AR -->|"③ Pull"| HUBIMG["jupyterhub-k8s-hub"]
    AR -->|"④ Pull"| PROXYIMG["jupyterhub-configurable-http-proxy"]
    AR -->|"⑤ Pull"| USERIMG["jupyterhub-k8s-singleuser-standard"]

    HUBIMG -->|"⑥"| HUB["GKE Pod<br/>hub"]
    PROXYIMG -->|"⑦"| PROXY["GKE Pod<br/>proxy"]
    USERIMG -->|"⑧"| USER["GKE Pod<br/>jupyter-user01..."]
```

---

# 11. 운영 시 주의사항

- `hub`, `proxy`는 Helm release `jupyterhub-task01`에서 관리됩니다.
- `kubectl scale ... --replicas=0`만 수행해도 이후 Provisioner/Helm 재적용 시 다시 `replicas=1`로 복구될 수 있습니다.
- `gke-gmp-system`, `gke-managed-cim`, `kube-system`은 GKE Autopilot 시스템 영역이므로 업무 중단 목적으로 삭제하지 않습니다.
- Infrastructure Manager 단계의 Cloud Build와 애플리케이션 이미지 빌드용 Cloud Build는 목적이 다릅니다.
- `gs://gcp-sbx-edp-gke01-bundles/cloudbuild/source`는 Build Source staging 용도이며, `gs://gcp-sbx-edp-gke01-requests/approved/`는 실제 Task 승인 트리거 입력 경로입니다.
