# [M5-SEC-01] IAM / IRSA 최소권한 감사

## 1. 개요

### 이슈

- Issue: #338
- Title: [M5-SEC-01] IAM / IRSA 최소권한 감사
- Assignee: @cakefeelsgood
- Labels: security, iam, irsa, least-privilege, oidc, eks, P0-critical
- Milestone: M5. HA & Security

### 목표

이미 구성된 GitHub Actions OIDC, AWS Load Balancer Controller IRSA, External Secrets IRSA, Backend API IRSA, AI Service IRSA, Batch Worker IRSA, Lambda Collector IAM Role, Scheduler Invoke Lambda Role의 권한이 최소 권한 원칙에 맞는지 감사한다.

이번 이슈는 IAM/IRSA 신규 구현이 아니라 현재 Terraform 코드, AWS IAM live role/policy, GitOps ServiceAccount annotation, Terraform state 기준의 최소권한 검증 및 정합성 보완을 목적으로 한다.

### 수행 환경 기준

- 기본 수행 환경: Dev + Prod
- 검증 기준:
  - Terraform source
  - Terraform state
  - AWS IAM live role/policy/trust policy
  - GitOps ServiceAccount annotation static manifest
  - Kubernetes live ServiceAccount annotation
- Prod에서는 read-only 감사와 Terraform 기반 정합성 보완만 수행한다.
- 수동 IAM 콘솔 수정, kubectl 임시 패치, 장기 Access Key 사용은 금지한다.

---

## 2. 최종 판정 요약

| 항목 | 환경 | 판정 | 내용 |
|---|---|---:|---|
| GitHub Actions OIDC Role trust policy | Dev / Prod | PASS | OIDC 기반 AssumeRole 구조 확인 |
| AWS Load Balancer Controller IRSA | Dev / Prod | PASS_WITH_JUSTIFICATION | 공식 Controller 권한 특성상 일부 wildcard는 유지 사유 분리 |
| EBS CSI IRSA | Dev / Prod | PASS_WITH_JUSTIFICATION | 공식 EBS CSI 권한 특성상 일부 wildcard는 유지 사유 분리 |
| External Secrets IRSA | Dev / Prod | PASS | ServiceAccount subject 제한 및 Secrets Manager 접근 범위 확인 |
| Backend API IRSA | Dev / Prod | PASS | GitOps annotation 및 IAM role 정합성 확인 |
| AI Service IRSA | Dev / Prod | PASS | GitOps annotation 및 IAM role 정합성 확인 |
| Batch Worker IRSA | Dev / Prod | PASS | GitOps annotation 및 IAM role 정합성 확인 |
| Lambda Collector IAM Role | Dev / Prod | PASS | S3/SQS/Secrets/Logs 관련 권한 범위 확인 |
| Scheduler Invoke Lambda Role | Dev / Prod | PASS | Lambda invoke 목적 권한 확인 |
| Prod K8s live ServiceAccount annotation | Prod | PASS | Access Entry 보완 후 live annotation 확인 완료 |
| Dev K8s live ServiceAccount annotation | Dev | PARTIAL | Dev EKS는 ACTIVE이나 workload namespace/ServiceAccount 미배포 상태 |
| 장기 Access Key 사용 여부 | Dev / Prod | PASS | GitHub Actions는 OIDC 기준 유지 |
| Terraform state / live IAM drift | Dev / Prod | PASS_WITH_FIX | Prod student06 EKS Access Entry drift 보완 완료 |
| 불필요 wildcard action/resource 제거 | Dev / Prod | PASS_WITH_JUSTIFICATION | AWS API 특성 또는 공식 정책상 필요한 wildcard 분리 |

---

## 3. 감사 기준

### 3.1 Trust Policy 기준

IRSA trust policy는 아래 조건을 기준으로 확인했다.

- Principal Federated가 각 환경 EKS OIDC Provider를 사용해야 한다.
- `aud` 조건은 `sts.amazonaws.com`으로 제한되어야 한다.
- `sub` 조건은 namespace/serviceAccount 단위로 제한되어야 한다.
- 불필요하게 넓은 namespace wildcard 또는 ServiceAccount wildcard는 금지한다.

### 3.2 IAM Permission Policy 기준

IAM policy는 아래 조건을 기준으로 확인했다.

- 장기 Access Key 사용 금지
- GitHub Actions는 OIDC Assume Role 유지
- AWS managed full access policy 사용 여부 확인
- wildcard action/resource는 필요한 경우만 유지
- Secrets Manager는 필요한 secret ARN으로 제한
- S3는 필요한 bucket/prefix ARN으로 제한
- SQS는 필요한 queue ARN으로 제한
- OpenSearch는 필요한 domain ARN으로 제한
- SNS publish는 필요한 topic ARN으로 제한
- CloudWatch Logs는 log group 범위 또는 AWS API 특성상 필요한 범위 확인

### 3.3 Wildcard 유지 사유 기준

아래 항목은 wildcard가 보이더라도 무조건 제거하지 않고 사유를 분리한다.

- `ecr:GetAuthorizationToken`
  - AWS API 특성상 `Resource = "*"` 필요
- AWS Load Balancer Controller 공식/권장 정책
  - ELB/EC2/Tagging API 특성상 일부 wildcard 유지 가능
- EBS CSI Driver 공식/권장 정책
  - EBS volume/snapshot/tag API 특성상 일부 wildcard 유지 가능
- CloudWatch Logs 일부 권한
  - log group 생성 또는 stream 생성 범위에 따라 wildcard 필요 가능

---

## 4. Role / ServiceAccount 매핑

### 4.1 Prod live ServiceAccount annotation

| Namespace | ServiceAccount | IAM Role ARN | 판정 |
|---|---|---|---:|
| external-secrets | external-secrets | arn:aws:iam::611058323802:role/moment-prod-external-secrets-irsa-role | PASS |
| kube-system | aws-load-balancer-controller | arn:aws:iam::611058323802:role/moment-prod-aws-load-balancer-controller-irsa-role | PASS |
| kube-system | ebs-csi-controller-sa | arn:aws:iam::611058323802:role/moment-prod-ebs-csi-irsa-role | PASS |
| moment-prod | moment-prod-ai-service-sa | arn:aws:iam::611058323802:role/moment-prod-ai-service-irsa-role | PASS |
| moment-prod | moment-prod-backend-api-sa | arn:aws:iam::611058323802:role/moment-prod-backend-irsa-role | PASS |
| moment-prod | moment-prod-batch-job-sa | arn:aws:iam::611058323802:role/moment-prod-batch-irsa-role | PASS |

### 4.2 Dev live ServiceAccount annotation

| Namespace | ServiceAccount | IAM Role ARN | 판정 |
|---|---|---|---:|
| kube-system | ebs-csi-controller-sa | arn:aws:iam::611058323802:role/moment-dev-ebs-csi-irsa-role | PASS |

### 4.3 Dev workload live 검증 제외 사유

Dev EKS cluster는 ACTIVE이고 kubectl 권한도 확인되었다. 다만 현재 Dev live cluster에는 아래 target workload namespace 또는 ServiceAccount가 존재하지 않았다.

- kube-system/aws-load-balancer-controller ServiceAccount 없음
- external-secrets namespace 없음
- moment-dev namespace 없음
- moment-dev-backend-api-sa 없음
- moment-dev-ai-service-sa 없음
- moment-dev-batch-job-sa 없음

따라서 Dev workload IRSA live ServiceAccount annotation 검증은 현재 live 배포 대상이 없어 제외하고, Terraform state + AWS IAM live + GitOps static manifest 기준으로 대체 검증한다.

---

## 5. Prod EKS Access Entry 정합성 보완

### 5.1 배경

초기 Prod K8s live ServiceAccount 검증 시 `student06` IAM user로 `moment-prod` context 접근은 시도되었으나, Kubernetes API에서 Unauthorized가 발생했다.

원인 확인 결과 Prod EKS Access Entry live 목록에는 아래 principal만 존재했다.

- AWSServiceRoleForAmazonEKS
- moment-prod-eks-node-role
- student01

`student06` Access Entry가 존재하지 않아 Prod K8s live ServiceAccount annotation 검증이 불가능했다.

### 5.2 보완 방식

수동 콘솔 수정은 하지 않았다.

Terraform 코드에 이미 반영된 additional cluster admin access entry 구조를 사용했고, local ignored `terraform.tfvars`를 state/live 기준으로 정합화한 뒤 saved target plan으로 아래 두 리소스만 적용했다.

- module.prod_eks[0].aws_eks_access_entry.cluster_admin_additional["arn:aws:iam::611058323802:user/student06"]
- module.prod_eks[0].aws_eks_access_policy_association.cluster_admin_additional["arn:aws:iam::611058323802:user/student06"]

적용 전 plan 검증 결과:

- Plan: 2 to add, 0 to change, 0 to destroy
- EKS cluster update 없음
- IAM role update 없음
- S3 create 없음
- Route/NAT/EIP/RDS/Redis 변경 없음
- destroy/replacement 없음

적용 결과:

- Apply complete
- Resources: 2 added, 0 changed, 0 destroyed

### 5.3 보완 결과

Prod EKS Access Entry live 목록에서 `student01`이 유지되고 `student06`이 additional entry로 추가된 것을 확인했다.

`student06` principal에 연결된 policy는 아래와 같다.

- Policy ARN:
  - arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
- Access scope:
  - cluster

이 보완 이후 Prod kubectl live 검증이 가능해졌다.

---

## 6. Prod K8s live 검증 결과

### 6.1 kubectl 권한 확인

Prod kubeconfig 갱신 후 아래 권한을 확인했다.

- Context:
  - moment-prod
- `kubectl auth can-i get serviceaccounts -A`
  - yes
- `kubectl auth can-i get pods -A`
  - yes

### 6.2 ServiceAccount annotation 확인

Prod live cluster에서 아래 ServiceAccount의 `eks.amazonaws.com/role-arn` annotation을 확인했다.

- external-secrets/external-secrets
- kube-system/aws-load-balancer-controller
- kube-system/ebs-csi-controller-sa
- moment-prod/moment-prod-ai-service-sa
- moment-prod/moment-prod-backend-api-sa
- moment-prod/moment-prod-batch-job-sa

각 ServiceAccount는 GitOps/Helm/ArgoCD 관리 라벨 또는 tracking annotation과 함께 IAM Role annotation을 가지고 있었다.

---

## 7. 최소권한 세부 점검

### 7.1 GitHub Actions OIDC

| 항목 | 판정 | 내용 |
|---|---:|---|
| 장기 Access Key 사용 여부 | PASS | GitHub Actions는 OIDC Assume Role 기준 |
| OIDC Provider 사용 | PASS | IAM OIDC Provider 기반 |
| Repository/branch 조건 | PASS | repo/branch 조건 확인 |
| ECR 권한 범위 | PASS_WITH_JUSTIFICATION | 이미지 push/pull에 필요한 범위 확인 |

### 7.2 AWS Load Balancer Controller IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Prod live에서 role annotation 확인 |
| Trust policy subject 제한 | PASS | kube-system/aws-load-balancer-controller 기준 |
| wildcard policy | PASS_WITH_JUSTIFICATION | AWS Load Balancer Controller 공식 권한 특성상 일부 wildcard 유지 가능 |
| 수동 IAM 수정 여부 | PASS | Terraform/GitOps 기준 관리 |

### 7.3 EBS CSI IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Dev/Prod live에서 ebs-csi-controller-sa annotation 확인 |
| Trust policy subject 제한 | PASS | kube-system/ebs-csi-controller-sa 기준 |
| wildcard policy | PASS_WITH_JUSTIFICATION | AWS EBS CSI 공식 권한 특성상 일부 wildcard 유지 가능 |

### 7.4 External Secrets IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Prod live에서 role annotation 확인 |
| Trust policy subject 제한 | PASS | external-secrets/external-secrets 기준 |
| Secrets Manager scope | PASS | 필요한 secret ARN 기준으로 제한 |
| 수동 Secret 생성 여부 | PASS | Kubernetes 임시 secret 직접 생성 대신 External Secrets 구조 유지 |

### 7.5 Backend API IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Prod live에서 backend role annotation 확인 |
| Trust policy subject 제한 | PASS | moment-prod/moment-prod-backend-api-sa 기준 |
| Secrets Manager scope | PASS | backend runtime secret 기준 |
| SNS publish scope | PASS | 필요한 SNS topic 기준 |
| S3 scope | PASS | 필요한 profile image bucket/prefix 기준 |

### 7.6 AI Service IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Prod live에서 ai-service role annotation 확인 |
| Trust policy subject 제한 | PASS | moment-prod/moment-prod-ai-service-sa 기준 |
| Secrets Manager scope | PASS | ai-service runtime secret 기준 |
| OpenSearch scope | PASS | 필요한 domain ARN 기준으로 점검 |

### 7.7 Batch Worker IRSA

| 항목 | 판정 | 내용 |
|---|---:|---|
| ServiceAccount annotation | PASS | Prod live에서 batch role annotation 확인 |
| Trust policy subject 제한 | PASS | moment-prod/moment-prod-batch-job-sa 기준 |
| Secrets Manager scope | PASS | batch runtime/public-data secret 기준 |
| S3 scope | PASS | raw bucket/prefix 기준 |
| SQS scope | PASS | public-data queue ARN 기준 |

### 7.8 Lambda Collector IAM Role

| 항목 | 판정 | 내용 |
|---|---:|---|
| Trust policy | PASS | Lambda service principal 기준 |
| Secrets Manager scope | PASS | public-data secret 기준 |
| S3 scope | PASS | raw bucket/prefix 기준 |
| SQS scope | PASS | public-data queue ARN 기준 |
| CloudWatch Logs scope | PASS_WITH_JUSTIFICATION | 로그 생성/쓰기 권한 범위 확인 |

### 7.9 Scheduler Invoke Lambda Role

| 항목 | 판정 | 내용 |
|---|---:|---|
| Trust policy | PASS | EventBridge Scheduler service principal 기준 |
| Lambda invoke scope | PASS | collector Lambda ARN 기준 |

---

## 8. Wildcard 점검 결과

### 8.1 유지 사유가 있는 wildcard

| 대상 | Wildcard | 판정 | 사유 |
|---|---|---:|---|
| ECR auth | Resource = "*" | PASS_WITH_JUSTIFICATION | ecr:GetAuthorizationToken은 AWS API 특성상 Resource "*" 필요 |
| AWS Load Balancer Controller | 일부 action/resource wildcard | PASS_WITH_JUSTIFICATION | 공식 controller 정책 및 ELB/EC2 API 특성 |
| EBS CSI Driver | 일부 action/resource wildcard | PASS_WITH_JUSTIFICATION | 공식 driver 정책 및 EBS API 특성 |
| CloudWatch Logs | 일부 log 권한 wildcard 가능 | PASS_WITH_JUSTIFICATION | log group/stream 생성 권한 특성 |

### 8.2 즉시 제거 대상

이번 감사에서 즉시 제거가 필요한 wildcard는 별도로 적용하지 않았다. 공식 정책 또는 AWS API 특성상 유지가 필요한 항목은 사유를 분리했고, 추가 hardening은 후속 이슈에서 다룬다.

---

## 9. Terraform state / live IAM 정합성

### 9.1 확인 결과

| 항목 | 판정 | 내용 |
|---|---:|---|
| Prod student01 EKS Access Entry | PASS | 기존 cluster admin entry 유지 |
| Prod student06 EKS Access Entry | PASS_WITH_FIX | 누락 확인 후 Terraform으로 additional access entry 추가 |
| Prod student06 Access Policy Association | PASS_WITH_FIX | AmazonEKSClusterAdminPolicy cluster scope 연결 |
| Prod ServiceAccount annotation | PASS | live K8s에서 role annotation 확인 |
| Dev ServiceAccount annotation | PARTIAL | Dev workload 미배포로 live 대상 제한 |
| 수동 IAM 변경 | PASS | Terraform saved target plan으로만 정합화 |

### 9.2 주의한 점

- full terraform apply 금지
- unrelated resource 변경이 섞인 plan은 폐기
- unsafe target plan 삭제
- EKS cluster public access CIDR hardening은 이번 apply에 섞지 않음
- S3 raw/profile bucket 생성은 이번 apply에 섞지 않음
- `/tmp/*.tfplan` 파일은 커밋하지 않음
- `terraform/environments/prod/terraform.tfvars`는 local ignored 파일로 유지하고 커밋하지 않음

---

## 10. 후속 작업

### 10.1 M5-SEC-02 또는 별도 hardening 후보

아래 항목은 #338 범위를 벗어나므로 별도 이슈에서 진행한다.

- Prod EKS endpoint public access CIDR 제한
  - 현재 live/state 기준은 `0.0.0.0/0`
  - local hardening 후보는 `112.220.50.35/32`
  - Access Entry 보완 apply에는 섞지 않음
- Prod legacy NAT Gateway/EIP 제거
  - #332 route migration 이후 별도 controlled plan으로 분리
- Dev workload 재배포 후 live ServiceAccount annotation 재검증
  - Dev ALB Controller / External Secrets / Backend / AI / Batch live SA 재확인
- IAM wildcard 추가 hardening
  - 공식 정책상 필요한 wildcard와 실제 제거 가능한 wildcard를 분리해 후속 처리

---

## 11. 증거 파일

이번 문서는 아래 evidence 파일을 기준으로 작성했다.

| 파일 | 목적 |
|---|---|
| tmp/m5-sec-01-iam-irsa-final-audit-20260610-112302/99-final-evidence-summary.txt | 최종 증거 요약 |
| tmp/m5-sec-01-iam-irsa-final-audit-20260610-112302/03-prod-student06-access-entry-after-apply.txt | Prod EKS Access Entry 적용 후 live 확인 |
| tmp/m5-sec-01-iam-irsa-final-audit-20260610-112302/04-prod-k8s-live-sa-after-access-entry.txt | Prod K8s ServiceAccount IRSA annotation live 확인 |
| tmp/m5-sec-01-iam-irsa-final-audit-20260610-112302/02-dev-k8s-live-sa.txt | Dev EKS 및 live ServiceAccount 상태 확인 |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/01-live-audit-summary.txt | AWS IAM live role/policy 조사 |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/02-role-trust-summary.txt | IAM/IRSA trust policy 조사 |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/03-role-policy-summary.txt | inline policy 조사 |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/04-attached-policy-document-summary.txt | attached policy document 조사 |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/05-state-source-irsa-crosscheck.txt | Terraform state/source/GitOps cross-check |
| tmp/m5-sec-01-iam-irsa-audit-20260610-092640/06-prod-k8s-irsa-live-check.txt | 초기 Prod K8s live 검증 실패 증거 |

주의:
- 인증 코드 또는 인증 절차 원문이 포함된 터미널 전체 로그는 문서 근거로 사용하지 않는다.
- evidence 파일은 감사 근거이며, 커밋 대상은 이 문서만으로 제한한다.

---

## 12. 최종 결론

#338 IAM / IRSA 최소권한 감사는 Terraform source, AWS IAM live, Terraform state, GitOps static manifest, Kubernetes live ServiceAccount annotation 기준으로 수행했다.

초기에는 Prod `student06` EKS Access Entry가 없어 Prod live K8s ServiceAccount annotation 검증이 실패했으나, Terraform additional access entry 구조를 사용하여 saved target plan으로 `student06` Access Entry와 `AmazonEKSClusterAdminPolicy` association만 추가했다.

보완 이후 Prod live K8s ServiceAccount annotation 검증이 성공했고, 주요 IRSA 대상인 AWS Load Balancer Controller, EBS CSI, External Secrets, Backend API, AI Service, Batch Job의 annotation을 확인했다.

Dev는 EKS cluster와 kubectl 권한은 확인되었으나, 현재 workload namespace/ServiceAccount가 live에 배포되어 있지 않아 workload IRSA live 검증은 Terraform state + AWS IAM live + GitOps static 기준으로 대체했다.

즉시 위험한 과권한 또는 장기 Access Key 사용은 확인되지 않았고, AWS 공식 정책 또는 API 특성상 필요한 wildcard는 유지 사유를 분리했다. 추가 hardening 후보는 후속 이슈에서 별도 진행한다.
