# task Load Balancer deployment

이 Root는 JupyterHub Service가 standalone NEG를 생성한 뒤 실행합니다.

입력값:

- GKE 서비스 프로젝트: `gcp-sbx-edp-gke01`
- 리전: `asia-northeast3`
- task 이름과 도메인
- GKE가 생성한 NEG self link
- Internal ALB frontend IP: `172.31.96.10`

Regional Internal Application Load Balancer의 URL map에 task별 host rule을 추가합니다. 인증서 정책과 사내 DNS가 확정되기 전에는 실제 forwarding rule을 생성하지 않습니다.
