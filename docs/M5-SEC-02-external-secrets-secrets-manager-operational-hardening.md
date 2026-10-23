# M5-SEC-02 External Secrets / Secrets Manager 운영 정합성 강화

## 1. 목적

MoMent Dev/Prod 환경의 External Secrets Operator(ESO), AWS Secrets Manager, IRSA, GitOps Secret Delivery, Helm workload secretRef 구성을 점검하고 운영 정합성을 강화한다.

이번 작업은 Secret 값을 노출하거나 Kubernetes Secret을 수동 생성하는 작업이 아니다.

Secret 값은 AWS Secrets Manager에서 운영자가 별도 관리한다.

GitOps/Terraform에는 Secret 값이 아니라 아래 항목만 관리한다.

- Secrets Manager secret name
- allowed secret ARN scope
- ExternalSecret remoteRef key/property
- target Kubernetes Secret name/key
- workload secretRef name/key
- 운영 절차와 검증 기준

## 2. 변경 요약

### 2.1 Prod External Secrets IRSA 권한 범위 축소

기존 Prod External Secrets IRSA 정책은 allow_rds_managed_secrets = true 로 인해 아래 RDS managed secret wildcard를 읽을 수 있었다.

- arn:aws:secretsmanager:ap-northeast-3:<account-id>:secret:rds!db-*

현재 GitOps ExternalSecret은 RDS managed master secret을 직접 참조하지 않는다.

현재 Prod GitOps ExternalSecret은 아래 runtime secret만 참조한다.

- moment/prod/backend-api
- moment/prod/ai-service
- moment/prod/batch-job

Monitoring Slack webhook secret은 GitOps Secret Delivery 대상이 아니라 Terraform alerting module에서 별도 관리된다.

따라서 Prod ESO IRSA에서 RDS managed secret wildcard 접근을 제거했다.

변경 파일:

- terraform/environments/prod/main.tf

변경 내용:

- before: allow_rds_managed_secrets = true
- after : allow_rds_managed_secrets = false

### 2.2 Dev ExternalSecret target 운영 옵션 보강

Prod ExternalSecret에는 target Secret 운영 옵션이 포함되어 있었으나, Dev ExternalSecret에는 일부 옵션이 빠져 있었다.

Dev/Prod Secret Delivery 동작을 맞추기 위해 Dev backend-api, ai-service, batch-job ExternalSecret에 아래 옵션을 추가했다.

- deletionPolicy: Retain
- template.engineVersion: v2
- template.mergePolicy: Replace
- template.type: Opaque

변경 파일:

- gitops/apps/dev/secret-delivery/backend-api-external-secret.yaml
- gitops/apps/dev/secret-delivery/ai-service-external-secret.yaml
- gitops/apps/dev/secret-delivery/batch-job-external-secret.yaml

## 3. Secret Delivery 구조

### 3.1 Dev

backend-api
- ExternalSecret: backend-api-dev-secret
- Target Kubernetes Secret: moment-dev-backend-api-secret
- Secrets Manager key: moment/dev/backend-api

ai-service
- ExternalSecret: ai-service-dev-secret
- Target Kubernetes Secret: moment-dev-ai-service-secret
- Secrets Manager key: moment/dev/ai-service

batch-job
- ExternalSecret: batch-job-dev-secret
- Target Kubernetes Secret: moment-dev-batch-job-secret
- Secrets Manager key: moment/dev/batch-job

### 3.2 Prod

backend-api
- ExternalSecret: backend-api-prod-secret
- Target Kubernetes Secret: moment-prod-backend-api-secret
- Secrets Manager key: moment/prod/backend-api

ai-service
- ExternalSecret: ai-service-prod-secret
- Target Kubernetes Secret: moment-prod-ai-service-secret
- Secrets Manager key: moment/prod/ai-service

batch-job
- ExternalSecret: batch-job-prod-secret
- Target Kubernetes Secret: moment-prod-batch-job-secret
- Secrets Manager key: moment/prod/batch-job

## 4. 검증 결과

### 4.1 Terraform targeted plan

Prod External Secrets IRSA policy만 대상으로 targeted plan을 수행했다.

결과 요약:

- module.prod_external_secrets_irsa[0].aws_iam_policy.this will be updated in-place
- rds!db-* wildcard ARN 제거 확인
- Plan: 0 to add, 1 to change, 0 to destroy

판정:

- OK: Prod External Secrets IRSA read policy에서 rds!db-* wildcard 제거만 확인됨
- OK: targeted plan 기준 destroy 없음
- OK: targeted plan 기준 create 없음

주의:

- target plan은 apply 목적이 아니다.
- target plan은 변경 영향 범위를 고립해서 확인하기 위한 진단용 증거로만 사용했다.

### 4.2 Full prod plan

Full prod plan에는 이번 이슈와 무관한 pending 변경이 포함되어 있었다.

확인된 unrelated pending changes:

- CloudWatch RDS/Redis alarm 4개 create
- RDS deletion_protection / final snapshot 설정 변경
- Redis failover / Multi-AZ / node_type / snapshot retention 변경
- Prod NAT EIP / NAT Gateway create

판정:

- NO APPLY
- Full prod plan은 M5-SEC-02 범위를 초과하므로 apply 금지
- 이번 PR에서는 코드 정합성 보강과 static/plan 검증까지만 수행한다

### 4.3 GitOps SecretRef consistency

Dev/Prod backend-api, ai-service, batch-job에 대해 ExternalSecret target.name과 Helm values secretRefs의 secretName/secretKey 매칭을 검증했다.

결과:

- ALL_SECRET_REF_CHECKS_PASSED

판정:

- OK: Workload values의 secretName은 ExternalSecret target.name과 일치한다
- OK: Workload values의 secretKey는 ExternalSecret data[].secretKey에 존재한다
- OK: Dev는 moment/dev/* 만 참조한다
- OK: Prod는 moment/prod/* 만 참조한다

### 4.4 Helm template rendering

아래 6개 chart/value 조합에 대해 helm template 렌더링을 수행했다.

- backend-api-dev=0
- ai-service-dev=0
- batch-job-dev=0
- backend-api-prod=0
- ai-service-prod=0
- batch-job-prod=0

판정:

- OK: Dev/Prod workload manifest 렌더링 성공
- OK: rendered manifest 내 secretKeyRef name/key 구조 확인

### 4.5 Terraform validate

Prod Terraform validate 결과:

- Success! The configuration is valid.

판정:

- OK: Prod Terraform configuration syntax/schema validation 성공

### 4.6 Secret value leak check

GitOps/Terraform tracked files 기준 정적 Secret 값 후보를 점검했다.

결과:

- terraform/modules/data-pipeline/lambda/collector.py:557: api_key = _resolve_api_key(source)

판정:

- OK: 실제 Secret 값이 아니라 코드 변수명 기반 false positive
- OK: Kubernetes Secret 값 또는 Secrets Manager secret value는 커밋하지 않음

## 5. 운영 절차

### 5.1 Secret 값 변경 절차

Secret 값은 GitOps 또는 Terraform 코드에 넣지 않는다.

운영자는 AWS Secrets Manager에서 환경별 runtime secret의 JSON property만 갱신한다.

대상 Secret name:

- moment/dev/backend-api
- moment/dev/ai-service
- moment/dev/batch-job
- moment/prod/backend-api
- moment/prod/ai-service
- moment/prod/batch-job

갱신 후 절차:

1. AWS Secrets Manager에서 해당 environment/workload Secret value 갱신
2. ExternalSecret refreshInterval 또는 강제 reconcile로 Kubernetes Secret 반영 확인
3. 대상 Deployment/CronJob/Worker Pod 재시작 또는 rollout으로 env 재주입
4. Pod 환경변수 값은 출력하지 않고 Secret key 존재 여부와 애플리케이션 health/smoke만 확인

### 5.2 RDS master password rotation 대응

현재 GitOps ExternalSecret은 RDS managed master secret을 직접 참조하지 않는다.

따라서 RDS master password가 rotation되거나 변경되면 아래 순서로 운영한다.

1. RDS master password 변경 또는 rotation 확인
2. application runtime secret의 db-password property 갱신
   - moment/<env>/backend-api
   - moment/<env>/batch-job
3. ExternalSecret reconcile 확인
4. backend-api / batch-job rollout
5. DB 연결 smoke 확인

Prod ESO IRSA에는 rds!db-* wildcard 읽기 권한을 부여하지 않는다.

### 5.3 검증 시 금지 사항

금지 사항:

- Secret value 출력 금지
- aws secretsmanager get-secret-value 결과 출력 금지
- kubectl get secret -o yaml 출력 금지
- kubectl create secret 수동 생성 금지
- GitOps/Terraform에 base64 Secret manifest 커밋 금지
- Full prod plan에 unrelated 변경이 섞인 상태에서 apply 금지

허용되는 검증 방식:

- ExternalSecret Ready 상태 확인
- SecretStore / ClusterSecretStore Ready 상태 확인
- Kubernetes Secret의 data key 목록만 확인
- Pod rollout / health / smoke 확인
- ESO controller logs에서 AccessDenied, NotFound, property missing 여부 확인

## 6. 증거 경로

이번 작업에서 생성한 주요 evidence 디렉터리:

- tmp/m5-sec-02-rds-secret-scope-20260610-223920
- tmp/m5-sec-02-tf-validate-plan-20260610-224150
- tmp/m5-sec-02-targeted-plan-20260610-224310
- tmp/m5-sec-02-gitops-secret-consistency-20260610-224455
- tmp/m5-sec-02-post-gitops-change-validation-20260610-224707

증거 파일은 로컬 검증용이며 PR 커밋 대상이 아니다.

## 7. 최종 판정

- OK: Prod ESO IRSA read policy wildcard scope 축소
- OK: Dev ExternalSecret target 운영 옵션을 Prod와 동일하게 보강
- OK: Dev/Prod ExternalSecret target Secret name과 workload secretRefs 매칭 확인
- OK: Dev/Prod remoteRef environment 분리 확인
- OK: Helm template 렌더링 성공
- OK: Terraform validate 성공
- OK: Secret value 미노출
- NO APPLY: Full prod plan에 unrelated pending changes 존재하므로 이번 PR에서 apply 금지

## 8. 커밋 대상

이번 PR 커밋 대상:

- terraform/environments/prod/main.tf
- gitops/apps/dev/secret-delivery/backend-api-external-secret.yaml
- gitops/apps/dev/secret-delivery/ai-service-external-secret.yaml
- gitops/apps/dev/secret-delivery/batch-job-external-secret.yaml
- docs/M5-SEC-02-external-secrets-secrets-manager-operational-hardening.md

커밋 제외 대상:

- tmp/

## 9. 후속 운영 메모

Full prod plan에는 M5-SEC-02 범위 밖 변경이 남아 있다.

따라서 이번 PR 머지 후에도 Terraform apply는 자동으로 수행하지 않는다.

Prod apply가 필요할 경우에는 별도 이슈에서 아래 변경들을 분리 검토해야 한다.

- CloudWatch RDS/Redis alarm 생성
- RDS deletion protection / final snapshot 설정 변경
- Redis failover / Multi-AZ / node type / snapshot retention 변경
- Prod NAT EIP / NAT Gateway 생성
