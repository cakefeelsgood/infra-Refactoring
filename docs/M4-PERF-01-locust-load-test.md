# M4-PERF-01 Locust 부하 테스트 시나리오 및 지표 관측

## 1. 목적

MoMent 주요 조회성 사용자 흐름에 대해 Locust 기반 부하 테스트를 수행하고, 부하 발생 시 Grafana와 CloudWatch에서 지표 변화가 관측되는지 확인한다.

이번 M4-PERF-01의 목적은 성능 한계 측정이나 튜닝이 아니라, 부하 상황에서 운영자가 다음 지표를 확인할 수 있는지 검증하는 것이다.

### Grafana 확인 지표

- request count
- request latency
- error rate
- Pod CPU
- Pod memory
- Pod restart count
- Deployment available replicas

### CloudWatch 확인 지표

- ALB RequestCount
- ALB TargetResponseTime
- HTTPCode_Target_4XX_Count
- HTTPCode_Target_5XX_Count
- HealthyHostCount
- UnHealthyHostCount

---

## 2. 테스트 대상 기준

### 기본 대상

Dev ALB를 1순위 부하 테스트 대상으로 사용한다.

~~~bash
http://<dev-alb-dns>
~~~

ALB를 통해 요청해야 CloudWatch의 ALB RequestCount, TargetResponseTime, 4xx, 5xx 지표 변화를 확인할 수 있다.

### 보조 대상

Dev ALB 접근이 어려운 경우 다음 대상을 보조로 사용할 수 있다.

- Dev Backend API endpoint
- 내부 테스트 endpoint
- port-forward 기반 local endpoint

단, ALB를 거치지 않는 테스트는 CloudWatch ALB 지표가 증가하지 않을 수 있다.

---

## 3. Prod 부하 테스트 정책

이번 M4-PERF-01에서는 Prod 환경에 실제 부하 테스트를 수행하지 않는다.

Prod 부하 테스트는 다음 조건을 만족할 때만 제한적으로 수행할 수 있다.

- 운영 승인 완료
- Prod EKS / ALB / Backend API 활성화 완료
- 테스트 시간대 사전 합의
- 조회성 API만 테스트
- 신청 / 결제 / 데이터 변경 API 제외
- 테스트 계정 또는 테스트 데이터 사용
- Grafana / CloudWatch / Alert 상태 확인 완료
- 중단 기준 사전 정의
- 장애 발생 시 즉시 중단 가능

Prod에서 수행 가능한 테스트는 대규모 부하 테스트가 아니라 제한적인 Smoke Test 수준으로 둔다.

~~~text
Prod Smoke Test 예시

users: 1~3
spawn rate: 1
run time: 1m~3m
target: 홈 조회, 프로그램 목록 조회, 프로그램 상세 조회
exclude: 신청 생성, 결제, 데이터 변경 API, 외부 비용 발생 API
~~~

강한 부하 테스트는 실제 Prod가 아니라 Dev 또는 Prod-like / Staging 환경에서 수행하는 것을 원칙으로 한다.

---

## 4. 포함 시나리오

기본 부하 테스트에는 조회성 API만 포함한다.

- 홈 조회
- 프로그램 목록 조회
- 프로그램 상세 조회
- 검색 요청
- 신청 가능 여부 조회

추천 조회는 기본적으로 비활성화한다.

추천 API가 DB / Cache 기반이면 포함할 수 있다.
외부 AI 호출 또는 비용 발생 API를 포함하면 제외하거나 Smoke Test 수준으로 제한한다.

---

## 5. 제외 시나리오

다음 API는 실제 데이터 변경 위험이 있으므로 기본 부하 테스트에서 제외한다.

- 신청 생성
- 결제 요청
- 결제 승인
- 북마크 생성 / 삭제
- 알림 생성
- 사용자 정보 변경
- 실제 데이터 저장 또는 상태 변경이 발생하는 API

---

## 6. Locust 설치

로컬에서 Locust를 설치한다.

~~~bash
python -m pip install --upgrade pip
python -m pip install locust
locust -V
~~~

가상환경을 사용할 경우:

~~~bash
python -m venv .venv
source .venv/Scripts/activate
python -m pip install --upgrade pip
python -m pip install locust
~~~

Mac / Linux 환경에서는 다음 명령을 사용할 수 있다.

~~~bash
source .venv/bin/activate
~~~

---

## 7. 환경 변수

실제 API path가 다를 경우 환경 변수로 path를 조정한다.

~~~bash
export MOMENT_HOME_PATH="/"
export MOMENT_PROGRAM_LIST_PATH="/programs"
export MOMENT_PROGRAM_DETAIL_PATH_TEMPLATE="/programs/{id}"
export MOMENT_SEARCH_PATH_TEMPLATE="/programs/search?keyword={keyword}"
export MOMENT_AVAILABILITY_PATH_TEMPLATE="/programs/{id}/availability"
~~~

테스트 데이터는 다음처럼 지정한다.

~~~bash
export MOMENT_PROGRAM_IDS="286,805"
export MOMENT_SEARCH_KEYWORDS="교육,박물관,양천구"
~~~

추천 API를 포함하려면 명시적으로 활성화한다.

~~~bash
export MOMENT_INCLUDE_RECOMMENDATION=false
export MOMENT_RECOMMENDATION_PATH="/recommendations"
~~~

인증이 필요한 API를 테스트할 경우 테스트 계정의 토큰만 사용한다.

~~~bash
export MOMENT_AUTH_TOKEN="<test-user-jwt-token>"
~~~

민감정보, 실제 사용자 정보, 실제 결제 정보는 사용하지 않는다.

---

## 8. 실행 방법

### Web UI 실행

~~~bash
locust -f monitoring/locust/locustfile.py \
  --host http://<dev-alb-dns>
~~~

브라우저에서 다음 주소로 접속한다.

~~~text
http://localhost:8089
~~~

---

## 9. Headless 실행 기준

### 9.1 Smoke Test

목적: Locust script와 endpoint 정상 여부 확인

~~~bash
locust -f monitoring/locust/locustfile.py \
  --host http://<dev-alb-dns> \
  --headless \
  -u 3 \
  -r 1 \
  --run-time 1m
~~~

기준:

- users: 1~3
- spawn rate: 1
- run time: 1m

---

### 9.2 Small Load Test

목적: Grafana / CloudWatch 지표 변화 확인

~~~bash
locust -f monitoring/locust/locustfile.py \
  --host http://<dev-alb-dns> \
  --headless \
  -u 20 \
  -r 5 \
  --run-time 5m
~~~

기준:

- users: 10~20
- spawn rate: 2~5
- run time: 3m~5m

---

### 9.3 Peak Demo Scenario

목적: 발표용 지표 변화 확인 및 HPA 연계 가능성 확인

~~~bash
locust -f monitoring/locust/locustfile.py \
  --host http://<dev-alb-dns> \
  --headless \
  -u 50 \
  -r 10 \
  --run-time 10m
~~~

기준:

- users: 30~50
- spawn rate: 5~10
- run time: 5m~10m

---

## 10. 테스트 중단 기준

다음 상황이 발생하면 테스트를 중단한다.

- HTTP 5xx가 지속적으로 증가하는 경우
- Pod가 CrashLoopBackOff 상태로 전환되는 경우
- Pod restart count가 급격히 증가하는 경우
- ALB Target이 Unhealthy 상태가 되는 경우
- DB / Redis 연결 오류가 반복되는 경우
- latency가 비정상적으로 증가하는 경우
- 예상보다 높은 비용 발생 가능성이 보이는 경우
- 운영 또는 팀 합의 없이 Prod 대상 테스트가 실행되는 경우

---

## 11. Grafana 확인 항목

테스트 전 / 중 / 후 다음 항목을 캡처한다.

#### 테스트 전
- `kubectl get pods -n moment-dev`
- `kubectl get ingress -n moment-dev`
- Dev ALB `/health`, `/programs` 200 응답 확인
- Grafana Pod CPU / Memory 기본 상태 확인
- CloudWatch ALB RequestCount / TargetResponseTime 기본 상태 확인

#### 테스트 중
- Locust 실행 화면 또는 headless summary
- Grafana request count / latency / error rate 변화 확인
- Grafana Pod CPU / Memory 변화 확인
- CloudWatch ALB RequestCount / TargetResponseTime 증가 확인

#### 테스트 후
- Locust HTML report 생성 확인
- Grafana Pod restart count 변화 여부 확인
- Grafana Deployment available replicas 확인
- CloudWatch HTTPCode_Target_4XX_Count / HTTPCode_Target_5XX_Count 확인
- CloudWatch HealthyHostCount / UnHealthyHostCount 확인
- 중단 기준 위반 여부 확인

- request count
- request latency
- error rate
- Pod CPU
- Pod memory
- Pod restart count
- Deployment available replicas
- HPA replica count 후보

---

## 12. CloudWatch 확인 항목

Dev ALB 기준으로 다음 지표를 확인한다.

- ALB RequestCount
- ALB TargetResponseTime
- HTTPCode_Target_4XX_Count
- HTTPCode_Target_5XX_Count
- HealthyHostCount
- UnHealthyHostCount

ALB를 거치지 않는 테스트를 수행한 경우 CloudWatch ALB 지표가 증가하지 않을 수 있다.

---

## 13. HPA 연계 기준

M4-HPA-01에서 Backend API HPA 검증 시 Locust 부하 기준을 재사용할 수 있다.

우선 다음 순서로 확인한다.

1. Smoke Test로 endpoint 정상 여부 확인
2. Small Load Test로 Grafana / CloudWatch 지표 변화 확인
3. Peak Demo Scenario로 HPA scale-out 가능성 확인
4. Scale-in 관측은 M4-HPA-01에서 후속 검증
M4-PERF-01 시점에서 HPA는 미설정 상태이며, Small Load Test 기준에서 Scale-out은 발생하지 않았다. Scale-out 관측 가능 여부 검증은 M4-HPA-01에서 수행한다.

---

## 14. 결과 기록 양식

테스트 결과는 다음 형식으로 기록한다.

~~~text
Test Type:
Target URL:
Users:
Spawn Rate:
Run Time:
Scenario:
Result:
Grafana Capture:
CloudWatch Capture:
Error Rate:
Average Latency:
p95 Latency:
Notes:
~~~

---

## 15. 산출물

- Locust 실행 방식
- Locust script
- 부하 테스트 대상 URL
- 조회성 시나리오 목록
- 제외 API 목록
- Smoke Test 기준
- Small Load Test 기준
- Peak Demo Scenario 기준
- 테스트 중단 기준
- Grafana 지표 변화 캡처
- CloudWatch ALB 지표 변화 캡처
- HPA 연계 기준
- Prod 부하 테스트 조건부 수행 기준
- Prod Smoke Test 절차
- README 또는 Wiki 문서
- PR 및 검증 로그
