# [M5-SEC-FOLLOWUP-01] IAM/IRSA 후속 Hardening 및 인프라 정합성 보완 최종 보고

## 1. 목적

[M5-SEC-FOLLOWUP-01]은 [M5-SEC-01] IAM/IRSA 최소권한 감사 이후 발견된 후속 보안/정합성 이슈를 실제 Prod 상태 기준으로 정리하고 보완하는 작업이다.

이번 작업은 다음 원칙으로 수행했다.

- 임시 kubectl patch 금지
- 가라 검증 금지
- Terraform full apply 금지
- target plan은 반드시 범위와 위험 필터를 확인한 뒤 적용
- Prod 변경은 saved plan 기반으로만 진행
- destroy/replacement/unrelated change가 섞이면 즉시 중단
- evidence는 tmp/ 하위에 남기되 커밋하지 않음

## 2. 완료 항목 요약

### 2.1 Prod IAM Policy source/live drift 정리

Prod IAM policy live body와 Terraform source 간 차이를 분리 확인 후 sync했다.

적용 결과:

- backend pod policy update
  - AllowProfileImageUpload 추가
  - AllowNotificationSnsPublish 추가
- batch pod policy update
  - AllowSqsConsume 추가
- lambda collector extra policy 생성
  - AllowSqsSend 추가
  - AllowLambdaCollectorSecretsManagerRead 추가
- lambda collector extra policy attachment 생성

적용 결과는 다음과 같다.

- 2 added
- 2 changed
- 0 destroyed

### 2.2 Prod S3 Raw/Profile bucket state ownership 복구

Prod raw/profile bucket은 live에 존재했지만 Terraform state에 없던 구간이 있었다.

복구 대상:

- module.prod_s3_raw_bucket[0]
- module.prod_profile_image_bucket[0]

조치:

- live S3 bucket 및 child resources를 Terraform state로 import
- S3-only normalization plan 적용
- data_pipeline post-S3 check 수행

결과:

- raw/profile bucket이 Terraform state에 정상 편입됨
- data_pipeline destroy 후보 제거됨
- post-S3 data_pipeline scoped check에서 No changes 확인

### 2.3 Prod Workload IRSA role 생성 및 ServiceAccount 정합성 복구

기존 문제:

- Kubernetes ServiceAccount annotation은 workload IRSA role ARN을 참조
- 하지만 live IAM에는 일부 workload IRSA role이 존재하지 않았음

생성 완료 role:

- moment-prod-ai-service-irsa-role
- moment-prod-aws-load-balancer-controller-irsa-role
- moment-prod-backend-irsa-role
- moment-prod-batch-irsa-role

생성 완료 attachment:

- ai-service role -> moment-prod-ai-service-pod-policy
- aws-load-balancer-controller role -> moment-prod-aws-load-balancer-controller-policy
- backend role -> moment-prod-backend-pod-policy
- batch role -> moment-prod-batch-pod-policy
- batch role -> moment-prod-raw-bucket-access-policy

적용 결과:

- 9 added
- 0 changed
- 0 destroyed

검증:

- kube-system/aws-load-balancer-controller annotation PASS
- moment-prod/moment-prod-backend-api-sa annotation PASS
- moment-prod/moment-prod-ai-service-sa annotation PASS
- moment-prod/moment-prod-batch-job-sa annotation PASS
- 각 IAM get-role 성공

### 2.4 Lambda Collector raw bucket access attachment 복구

S3 raw bucket state ownership 복구 후 Terraform source 기준으로 Lambda Collector Role에 raw bucket access policy attachment가 필요함을 확인했다.

조치:

- module.prod_iam[0].aws_iam_role_policy_attachment.lambda_raw_bucket["raw"] 생성

적용 결과:

- 1 added
- 0 changed
- 0 destroyed

검증:

moment-prod-lambda-collector-role에 다음 policy가 attached 상태임을 확인했다.

- AWSLambdaBasicExecutionRole
- moment-prod-raw-bucket-access-policy
- moment-prod-lambda-collector-extra-policy

### 2.5 Prod EKS API Endpoint CIDR hardening

기존 상태:

- endpointPublicAccess: true
- endpointPrivateAccess: true
- publicAccessCidrs: 0.0.0.0/0

변경 후:

- endpointPublicAccess: true
- endpointPrivateAccess: true
- publicAccessCidrs: 112.220.50.35/32

적용 결과:

- 0 added
- 1 changed
- 0 destroyed

검증:

- aws eks update-kubeconfig 성공
- kubectl current-context = moment-prod
- kubectl auth can-i get serviceaccounts -A = yes
- kubectl auth can-i get pods -A = yes

주의:

운영자 공인 IP가 변경되면 prod_eks_public_access_cidrs를 의도적으로 갱신해야 한다.

### 2.6 Legacy Prod NAT Gateway / EIP cleanup

#332 이후 Prod private app default route는 TGW로 전환되었으나 legacy NAT Gateway/EIP가 state/live에 남아 있었다.

삭제 대상:

- module.prod_vpc[0].aws_nat_gateway.this
- module.prod_vpc[0].aws_eip.nat

적용 결과:

- 0 added
- 0 changed
- 2 destroyed

검증:

- Terraform state에는 module.prod_vpc[0].aws_route.private_app_default_to_tgw[0]만 남음
- live private app default route는 0.0.0.0/0 -> tgw-0aabb035ee186b0e1 유지
- NAT Gateway state는 deleted
- EIP allocation은 InvalidAllocationID.NotFound 확인

### 2.7 Legacy live-only ALB Controller IRSA role cleanup

삭제 대상:

- moment-prod-alb-controller-irsa-role

삭제 전 확인:

- Terraform state에 없음
- attached managed policy 없음
- inline policy 없음
- Kubernetes ServiceAccount는 moment-prod-aws-load-balancer-controller-irsa-role 사용
- AWS Load Balancer Controller pods Running

삭제 후 확인:

- aws iam get-role 결과 NoSuchEntity
- Kubernetes ServiceAccount는 새 role 유지
- AWS Load Balancer Controller pods Running 유지

## 3. IAM Wildcard 분류

### 3.1 CloudWatch Logs prefix wildcard

확인 위치:

- terraform/modules/iam/main.tf

대상:

- /aws/eks/moment-prod*
- /aws/lambda/moment-prod*

판정:

- 전체 Resource "*"가 아니라 project/environment prefix 기반 wildcard
- CloudWatch log group suffix 및 stream ARN 대응을 위한 제한적 wildcard로 분류
- 현 단계에서는 ACCEPT_WITH_DOCUMENTATION

### 3.2 ECR GetAuthorizationToken Resource "*"

확인 위치:

- terraform/modules/iam/main.tf

대상:

- ecr:GetAuthorizationToken
- resources = ["*"]

판정:

- ECR authorization token 성격상 resource-level restriction이 제한되는 대표 케이스
- 현 단계에서는 ACCEPT_WITH_DOCUMENTATION

### 3.3 AWS Load Balancer Controller policy wildcard

판정:

- AWS Load Balancer Controller의 ELB/EC2 관련 controller policy 성격상 일부 wildcard가 필요
- tag condition 및 controller scope를 기반으로 운용
- 현 단계에서는 ACCEPT_WITH_DOCUMENTATION
- 추후 공식 policy version drift 점검은 별도 hardening 후보로 분리 가능

## 4. 최종 Scoped Verification

대상:

- module.prod_vpc[0]
- module.prod_eks[0].aws_eks_cluster.this
- module.prod_iam[0]
- module.prod_workload_irsa[0]
- module.prod_external_secrets_irsa[0]
- module.prod_s3_raw_bucket[0]
- module.prod_profile_image_bucket[0]
- module.prod_data_pipeline[0]
- module.prod_sqs[0]
- module.prod_notification_sns[0]

결과:

- No changes. Your infrastructure matches the configuration.

## 5. 최종 판정

[M5-SEC-FOLLOWUP-01]에서 목표로 한 IAM/IRSA 후속 Hardening 및 인프라 정합성 보완은 완료로 판정한다.

완료된 핵심 결과:

- Prod workload IRSA 실체와 ServiceAccount annotation 정합성 복구
- Prod IAM policy source/live drift 해소
- Prod S3/DataPipeline state/source/live 정합성 복구
- Prod EKS API endpoint CIDR hardening 완료
- Legacy Prod NAT/EIP cleanup 완료
- Legacy live-only old ALB IRSA role cleanup 완료
- IAM wildcard는 현 단계 ACCEPT_WITH_DOCUMENTATION으로 분류
