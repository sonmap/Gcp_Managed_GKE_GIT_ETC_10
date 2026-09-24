# GCP EDP Sandbox Platform - 4th Terraform Test

두 프로젝트 기반의 GKE Sandbox 플랫폼입니다.

| 프로젝트 | 역할 |
|---|---|
| `gcp-prod-edp-hub-vpchost` | Shared VPC Host, 172/10 대역 네트워크 |
| `gcp-sbx-edp-gke01` | GKE Autopilot, Internal ALB, Cloud Run, Cloud Build, Artifact Registry, Infrastructure Manager |
| `gcp-sbx-edp-comn-509423` | task01 BigQuery 및 GCS |

## 실행 경계

| 순서 | Root | 실행 위치 | 인증 | 방식 |
|---:|---|---|---|---|
| 00 | `terraform/00-bootstrap` | instance-son | `admin@sonmap.net` | 수동 Terraform |
| 10 | `terraform/10-network-host` | instance-son | `admin@sonmap.net` | 수동 Terraform |
| 20 | `terraform/20-admin-iam` | instance-son | `admin@sonmap.net` | 수동 Terraform |
| 30 | `terraform/30-foundation` | instance-son에서 요청 | VM SA → `sa-im-foundation` | Infrastructure Manager |
| 40 | `terraform/40-task/*` | 자동화 | 단계별 전용 SA | 승인 JSON 기반 Infrastructure Manager |

VM 기본 서비스 계정은 `40744085720-compute@developer.gserviceaccount.com`입니다.

## 디렉터리

```text
terraform/
├── 00-bootstrap/
├── 10-network-host/
├── 20-admin-iam/
├── 30-foundation/
└── 40-task/
    ├── 10-project/
    ├── 20-project-iam/
    ├── 30-data/
    ├── 40-gke/
    └── 50-loadbalancer/
examples/task01-approved-request.json
docs/execution-and-iam.md
```

## 안전 원칙

- 00/10/20의 Plan은 관리자 검토 후 적용합니다.
- 30 이후에는 사용자 ADC와 `GOOGLE_OAUTH_ACCESS_TOKEN`을 제거합니다.
- Infrastructure Manager 소스는 이동하는 branch 대신 승인된 commit SHA를 사용합니다.
- 로컬 `terraform.tfvars`, State, Plan, 인증키는 Git에 저장하지 않습니다.
