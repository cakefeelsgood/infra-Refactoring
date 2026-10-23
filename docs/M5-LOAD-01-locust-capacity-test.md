# M5-LOAD-01 Locust 단계별 부하 / 용량 한계 / HPA 병목 검증

## 테스트 목적

MoMent Backend API의 주요 조회성 사용자 흐름에 대해 Locust 기반 단계별 부하 테스트를 수행하고,
Dev ALB / EKS / HPA / Pod / Node / RDS / Redis / OpenSearch / Grafana / CloudWatch 기준으로
현재 인프라가 어느 수준까지 안정적으로 버티는지 확인한다.

## 테스트 환경

- 리전: ap-northeast-3 (오사카)
- EKS 클러스터: moment-dev-eks-cluster
- Namespace: moment-dev
- Dev ALB: k8s-momentde-backenda-19db73e401-1868529661.ap-northeast-3.elb.amazonaws.com
- Locust 실행 환경: Windows (DESKTOP-KHECPIQ), Python 3.13, Locust headless

## 테스트 일시

2026-06-12

## 테스트 대상 API

- GET /health
- GET /actuator/health
- GET /programs/home
- GET /programs?status=RECRUITING
- GET /programs?status=RECRUITING&filter=urgent
- GET /programs?status=RECRUITING&filter=free
- GET /programs?status=RECRUITING&filter=online
- GET /programs?status=RECRUITING&filter=public
- GET /programs/{id}

## 제외 API

- 신청 생성 API
- 결제 API
- 북마크 생성/삭제 API
- 알림 생성/읽음 처리 API
- 사용자 정보 변경 API
- 외부 유료 API 호출 가능성이 있는 API
- OpenAI 또는 외부 LLM 호출이 발생할 수 있는 AI 요청 API

## Locust 실행 명령

```bash
python -m locust -f monitoring/locust/locustfile.py \
  --host=http://<DEV_ALB_DNS> \
  --users <users> --spawn-rate <spawn_rate> --run-time <run_time> --headless \
  --html monitoring/locust/results/m5-load/<stage>.html \
  --csv monitoring/locust/results/m5-load/<stage>
```

## 최종 결과 요약

| 단계 | users | failure | avg(ms) | p50(ms) | p95(ms) | p99(ms) | req/s | HPA | 결과 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| smoke | 3 | 0% | 119 | - | - | - | 1.36 | 1 | ✅ |
| small | 20 | 0% | 167 | - | 160 | 420 | 9.23 | 1 | ✅ |
| hpa | 50 | 0% | 148 | - | 120 | 500 | 23.15 | 3 | ✅ |
| medium | 100 | 0% | 178 | - | 200 | 3100 | 45.74 | 4 | ✅ |
| high | 300 | 0.00% | 879 | - | 2400 | 20000 | 102.29 | 8 | ✅ |
| stress | 500 | 0.02% | 1586 | - | 6200 | 26000 | 136.05 | 9 | ✅ |
| baseline-1000 | 1000 | 0.03% | 3839 | - | 23000 | 37000 | 164.03 | 10 | ✅ |
| scale-5000 | 5000 | 73.62% | 50195 | - | 67000 | 69000 | 84.97 | 10 | ❌ 중단 |
| scale-10000 | 10000 | 87.43% | 58968 | 60000 | 128000 | 130000 | 132.94 | 6 | ❌ 중단 |

**최종 도달 가능 users 수준**: 1,000명
(baseline-1000까지 안정적 통과. 5,000명부터 한계 초과.)

## 단계별 중단 사유

### scale-5000
- failure rate 73.62% 지속
- avg latency 50,195ms, p99 69,000ms
- HPA maxReplicas(10) 도달 후 추가 스케일 불가
- 운영자 수동 중단

### scale-10000
- failure rate 87.43% 지속 (중단 기준 5% 초과)
- avg latency 58,968ms, p50/p95/p99 각각 60초/128초/130초 — ALB idle timeout 수준 도달
- backend-api CPU 134~198% (limits 대비 199%)
- HPA replica 6개 (scale-5000 대비 오히려 감소 — 이전 부하 잔존 영향)
- 운영자 수동 Ctrl+C, exit code 1

## 병목 분석

- **병목 지점**: scale-5000 진입 직후부터 failure rate 급등, scale-10000에서 완전 포화
- **병목 원인**:
  - backend-api Pod CPU limits 초과 (scale-10000 시 134~198%, limits 대비 199%)
  - HPA maxReplicas 10 도달 후 추가 스케일 불가
  - avg latency가 ALB idle timeout(60초) 수준까지 도달 → 연결 강제 종료로 failure 폭증
  - Pod 10개로도 10,000 동시 사용자 처리 불가
- **증설 필요 항목**:
  - backend-api HPA maxReplicas 상향 (현재 10 → 20 이상)
  - backend-api CPU requests/limits 상향 또는 Node 증설
  - RDS connection pool 한계 검토
- **튜닝 필요 항목**:
  - backend-api JVM heap / thread pool 튜닝
  - ALB idle timeout 조정 또는 connection reuse 최적화
  - DB connection pool 설정 (HikariCP maxPoolSize) 검토
  - Redis 캐싱 적용 범위 확대 검토
- **후속 이슈**:
  - backend-api HPA maxReplicas 및 resource limits 튜닝
  - RDS / Redis 병목 상세 분석
  - 5,000명 이상 대응을 위한 인프라 증설 계획

## Prod 부하 테스트 제외 사유

Prod는 운영 승인, 시간 합의, 중단 기준, 모니터링 준비가 된 경우에만 제한적인 smoke test를 수행한다.
대규모 부하(1,000 / 5,000 / 10,000 users) 테스트는 Dev ALB 기준으로만 수행한다.

## 민감정보 미포함 확인

- [x] JWT 토큰 미포함 확인
- [x] API Key 미포함 확인
- [x] DB Password 미포함 확인
- [x] Slack Webhook URL 미포함 확인
- [x] 로그 및 캡처 파일 내 민감정보 미포함 확인
