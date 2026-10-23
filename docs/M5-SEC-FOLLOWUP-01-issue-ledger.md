# [M5-SEC-FOLLOWUP-01] IAM/IRSA 후속 Hardening 및 인프라 정합성 이슈 원장

## 목적

[M5-SEC-FOLLOWUP-01] 진행 중 확인된 Prod/Dev IAM, IRSA, EKS Endpoint, Terraform state/source/live 정합성 문제를 하나의 apply로 처리하지 않고, 실무적으로 분리된 이슈 단위로 추적한다.

본 문서는 가라 검증, 임시 우회, kubectl patch, 콘솔 수동 생성, 무분별한 full apply를 금지하고, 각 항목을 source / state / live / GitOps 증거 기반으로 처리하기 위한 원장이다.

## 공통 원칙

- Prod full plan에 unrelated change, destroy, replacement, mass change가 섞이면 apply 금지.
- Prod 변경은 saved plan 기준으로만 검토한다.
- endpoint CIDR, workload IRSA, IAM policy, data pipeline, NAT/EIP cleanup은 한 apply로 섞지 않는다.
- local ignored terraform.tfvars 변경은 문서 근거로 기록하되 commit하지 않는다.
- tmp evidence, tfplan, tfstate, tfvars, secret 값은 commit하지 않는다.
- kubectl patch나 콘솔 수동 생성은 최종 해결책으로 사용하지 않는다.

## ISSUE-A. Prod EKS Endpoint CIDR Hardening

### 최종 상태

COMPLETE

### 기존 문제

Prod EKS API endpoint가 다음 상태였다.

- endpointPublicAccess: true
- endpointPrivateAccess: true
- publicAccessCidrs: 0.0.0.0/0

이는 Prod EKS API server가 인터넷 전체에서 접근 가능한 상태라서 hardening 대상이었다.

### 조치

endpoint-only target saved plan으로 변경 범위를 분리했다.

변경 대상:

- module.prod_eks[0].aws_eks_cluster.this

변경 내용:

- public_access_cidrs
  - before: 0.0.0.0/0
  - after: 112.220.50.35/32

적용 결과:

- 0 added
- 1 changed
- 0 destroyed

### 검증

적용 후 live 상태:

- endpointPublicAccess: true
- endpointPrivateAccess: true
- publicAccessCidrs: 112.220.50.35/32

접근 검증:

- aws eks update-kubeconfig 성공
- kubectl current-context = moment-prod
- kubectl auth can-i get serviceaccounts -A = yes
- kubectl auth can-i get pods -A = yes

### 최종 판정

Prod EKS API endpoint는 더 이상 0.0.0.0/0에 공개되지 않는다.

단, 운영자 공인 IP가 변경되면 prod_eks_public_access_cidrs를 Terraform으로 의도적으로 갱신해야 한다.

## ISSUE-B. Prod Workload IRSA Role 정합성 깨짐

### 최종 상태

COMPLETE

### 기존 문제

Prod Kubernetes ServiceAccount annotation은 아래 IAM Role ARN을 참조하고 있었다.

- kube-system/aws-load-balancer-controller
  - arn:aws:iam::611058323802:role/moment-prod-aws-load-balancer-controller-irsa-role
- moment-prod/moment-prod-backend-api-sa
  - arn:aws:iam::611058323802:role/moment-prod-backend-irsa-role
- moment-prod/moment-prod-ai-service-sa
  - arn:aws:iam::611058323802:role/moment-prod-ai-service-irsa-role
- moment-prod/moment-prod-batch-job-sa
  - arn:aws:iam::611058323802:role/moment-prod-batch-irsa-role

하지만 IAM live에는 위 workload IRSA role들이 존재하지 않았고, Terraform state에도 module.prod_workload_irsa 리소스가 없었다.

### 조치

Terraform module.prod_workload_irsa를 기준으로 workload IRSA role과 policy attachment를 생성했다.

생성 role:

- moment-prod-ai-service-irsa-role
- moment-prod-aws-load-balancer-controller-irsa-role
- moment-prod-backend-irsa-role
- moment-prod-batch-irsa-role

생성 attachment:

- ai_service -> moment-prod-ai-service-pod-policy
- aws_load_balancer_controller -> moment-prod-aws-load-balancer-controller-policy
- backend -> moment-prod-backend-pod-policy
- batch -> moment-prod-batch-pod-policy
- batch -> moment-prod-raw-bucket-access-policy

적용 결과:

- 9 added
- 0 changed
- 0 destroyed

### 검증

ServiceAccount annotation과 IAM role 실존 여부를 검증했다.

PASS:

- kube-system/aws-load-balancer-controller
- moment-prod/moment-prod-backend-api-sa
- moment-prod/moment-prod-ai-service-sa
- moment-prod/moment-prod-batch-job-sa

각 IAM role에 대해 get-role 성공을 확인했다.

### 최종 판정

Prod workload IRSA의 source / state / live / GitOps 정합성이 복구되었다.

## ISSUE-C. Prod IAM Policy source/live drift

### 최종 상태

COMPLETE

### 기존 문제

Terraform source는 SNS/SQS/Lambda Collector extra policy 구성을 포함하고 있었지만, live IAM policy body와 attachment 일부가 source와 맞지 않았다.

확인된 drift:

- backend pod policy에 SNS publish / profile image upload 권한이 live에 없음
- batch pod policy에 SQS consume 권한이 live에 없음
- lambda collector extra policy가 live에 없음
- lambda collector role에 일부 required attachment가 없음

### 조치

IAM policy sync를 별도 target plan으로 분리하여 적용했다.

적용 내용:

- backend pod policy update
  - AllowProfileImageUpload
  - AllowNotificationSnsPublish
- batch pod policy update
  - AllowSqsConsume
- lambda collector extra policy create
  - AllowSqsSend
  - AllowLambdaCollectorSecretsManagerRead
- lambda collector extra policy attachment create

적용 결과:

- 2 added
- 2 changed
- 0 destroyed

추가 조치:

- Lambda Collector raw bucket access attachment 복구
  - module.prod_iam[0].aws_iam_role_policy_attachment.lambda_raw_bucket["raw"]

추가 적용 결과:

- 1 added
- 0 changed
- 0 destroyed

### 검증

moment-prod-lambda-collector-role에 다음 policy가 attached 되었음을 확인했다.

- AWSLambdaBasicExecutionRole
- moment-prod-raw-bucket-access-policy
- moment-prod-lambda-collector-extra-policy

### 최종 판정

Prod IAM policy source/live drift가 해소되었다.

## ISSUE-D. Prod S3 Raw/Profile bucket state ownership 및 data_pipeline 정합성

### 최종 상태

COMPLETE

### 기존 문제

Prod raw/profile S3 bucket은 live에 존재했지만 Terraform state에 없었다.

동시에 data_pipeline module은 raw bucket module 의존 관계를 가진 상태라, source/state/live 불일치로 인해 full plan에서 data_pipeline destroy 위험이 나타났다.

대상 bucket:

- moment-prod-raw-data-611058323802-ap-northeast-3
- moment-prod-profile-image-611058323802-ap-northeast-3

### 조치

live S3 bucket 및 하위 리소스를 Terraform state로 import했다.

Raw bucket import 대상:

- aws_s3_bucket.raw
- aws_s3_bucket_public_access_block.raw
- aws_s3_bucket_versioning.raw
- aws_s3_bucket_server_side_encryption_configuration.raw
- aws_s3_bucket_lifecycle_configuration.raw
- aws_s3_object.prefix["raw"]
- aws_s3_object.prefix["processed"]
- aws_s3_object.prefix["failed"]
- aws_iam_policy.raw_bucket_access

Profile bucket import 대상:

- aws_s3_bucket.this
- aws_s3_bucket_public_access_block.this
- aws_s3_bucket_versioning.this
- aws_s3_bucket_server_side_encryption_configuration.this
- aws_s3_bucket_lifecycle_configuration.this

이후 S3-only normalization plan을 적용했다.

적용 결과:

- 0 added
- 3 changed
- 0 destroyed

### 검증

S3 import 및 normalization 이후 data_pipeline / raw bucket / SQS scoped check에서 다음 결과를 확인했다.

- No changes. Your infrastructure matches the configuration.

### 최종 판정

Prod S3 raw/profile bucket의 source / state / live ownership이 복구되었고, data_pipeline destroy 위험이 제거되었다.

## ISSUE-E. Workload IRSA target plan dependency graph isolation

### 최종 상태

COMPLETE

### 기존 문제

module.prod_workload_irsa에 broad module-level depends_on이 존재하여 workload IRSA target plan에서 unrelated pending change가 같이 끌려오는 문제가 있었다.

기존 depends_on:

- module.prod_iam
- module.prod_eks
- module.prod_s3_raw_bucket

### 조치

broad module-level depends_on을 제거하고, 실제 dependency는 명시 input reference로 표현되도록 정리했다.

명시 dependency:

- module.prod_eks[0].eks_oidc_provider_arn
- module.prod_eks[0].eks_oidc_provider_url
- module.prod_iam[0].policy_arns
- module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn when enabled

변경 의도:

- Terraform graph에서 불필요한 module-wide dependency 전파를 줄임
- controlled target plan에서 unrelated change 유입을 줄임
- source 구조를 실제 참조 관계 기준으로 맞춤

### 검증

- terraform validate 성공
- workload IRSA clean plan에서 role/attachment 생성 범위로 분리 가능해짐
- 최종 scoped check에서 No changes 확인

### 최종 판정

workload IRSA target plan 격리성이 개선되었다.

## ISSUE-F. Legacy ALB Controller IRSA Role 잔존

### 최종 상태

COMPLETE

### 기존 문제

live IAM에 아래 legacy role이 남아 있었다.

- moment-prod-alb-controller-irsa-role

하지만 현재 GitOps/Kubernetes ServiceAccount는 새 표준 role을 참조한다.

- moment-prod-aws-load-balancer-controller-irsa-role

### 삭제 전 확인

legacy role 상태:

- Terraform state에 없음
- attached managed policy 없음
- inline policy 없음
- RoleLastUsed는 과거 시점
- 현재 Kubernetes ServiceAccount는 moment-prod-aws-load-balancer-controller-irsa-role 사용
- AWS Load Balancer Controller pods Running

### 조치

live-only orphan으로 판단하고 legacy role을 삭제했다.

삭제 대상:

- moment-prod-alb-controller-irsa-role

### 검증

삭제 후:

- aws iam get-role 결과 NoSuchEntity
- Kubernetes ServiceAccount는 moment-prod-aws-load-balancer-controller-irsa-role 유지
- AWS Load Balancer Controller pods Running 유지

### 최종 판정

legacy live-only ALB Controller IRSA role cleanup이 완료되었다.

## ISSUE-G. IAM wildcard classification

### 최종 상태

COMPLETE / ACCEPT_WITH_DOCUMENTATION

### CloudWatch Logs prefix wildcard

대상:

- /aws/eks/moment-prod*
- /aws/lambda/moment-prod*

판정:

- 전체 Resource "*"가 아니라 project/environment prefix 기반 wildcard
- CloudWatch log group suffix 및 log stream ARN 대응을 위한 제한적 wildcard
- 현 단계 ACCEPT_WITH_DOCUMENTATION

### ECR GetAuthorizationToken Resource "*"

대상:

- ecr:GetAuthorizationToken
- resources = ["*"]

판정:

- ECR authorization token 성격상 resource-level restriction이 제한되는 대표 케이스
- 현 단계 ACCEPT_WITH_DOCUMENTATION

### AWS Load Balancer Controller policy wildcard

판정:

- AWS Load Balancer Controller의 ELB/EC2 controller policy 성격상 일부 wildcard 필요
- tag condition 및 controller scope를 기반으로 운용
- 현 단계 ACCEPT_WITH_DOCUMENTATION
- 추후 공식 policy version drift 점검은 별도 hardening 후보로 분리 가능

### 최종 판정

이번 #630에서는 wildcard를 무리하게 축소하지 않고, 성격별로 분류 및 문서화했다.

## ISSUE-H. Dev Workload IRSA reverify / Prod NAT-EIP cleanup

### 최종 상태

PARTIAL_COMPLETE

### Dev Workload IRSA reverify

현재 상태:

- Dev EKS는 ACTIVE
- 현재 Dev workload namespace/app 미배포
- live ServiceAccount annotation은 EBS CSI만 확인

판정:

- BLOCKED_BY_RUNTIME_NOT_DEPLOYED
- Dev runtime/GitOps 재배포 시점에 backend/ai/batch/external-secrets/alb-controller ServiceAccount annotation 재검증 필요

### Prod NAT/EIP cleanup

기존 상태:

- #332 이후 Prod private-app default route는 TGW로 전환됨
- 하지만 legacy NAT Gateway / EIP가 state/live에 남아 있었음

삭제 대상:

- module.prod_vpc[0].aws_nat_gateway.this
- module.prod_vpc[0].aws_eip.nat

적용 결과:

- 0 added
- 0 changed
- 2 destroyed

검증:

- Terraform state에는 module.prod_vpc[0].aws_route.private_app_default_to_tgw[0]만 남음
- live route는 0.0.0.0/0 -> tgw-0aabb035ee186b0e1 유지
- NAT Gateway state는 deleted
- EIP allocation은 InvalidAllocationID.NotFound 확인

### 최종 판정

- Dev Workload IRSA live reverify는 runtime 미배포로 blocked 상태를 명확히 기록했다.
- Prod NAT/EIP cleanup은 완료되었다.

## 최종 Scoped Verification

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

## 최종 판정

[M5-SEC-FOLLOWUP-01]은 완료로 판정한다.

완료된 항목:

- Prod EKS endpoint CIDR hardening
- Prod workload IRSA role/source/state/live/GitOps 정합성 복구
- Prod IAM policy source/live drift 해소
- Prod S3 raw/profile bucket source/state/live ownership 복구
- Prod data_pipeline destroy risk 제거
- Lambda Collector raw bucket access attachment 복구
- workload IRSA Terraform dependency graph 격리성 개선
- legacy live-only ALB Controller IRSA role cleanup
- legacy Prod NAT/EIP cleanup
- IAM wildcard classification 문서화

잔여 follow-up:

- Dev runtime/GitOps 재배포 후 Dev workload IRSA live annotation 재검증
