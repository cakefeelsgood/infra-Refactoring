# ECR Dev/Prod Repository 및 배포 준비 정책

## 1. 개요

MoMent 서비스의 컨테이너 이미지는 Amazon ECR Repository에 저장한다.

현재 최종 설계 기준에서 ECR은 Shared environment에 두지 않고 Dev / Prod 환경별로 분리한다.

- Dev ECR: 개발 및 검증 이미지 저장
- Prod ECR: 최종 데모 또는 리허설 시점의 운영 후보 이미지 저장
- Shared ECR: 사용하지 않음

이번 기준은 ECR Repository를 배포 전에 사전 생성할 수 있도록 정리하는 것이 목적이다.

단, 이번 이슈에서는 GitHub Actions workflow 생성, CI/CD 배포 구현, Docker image push, EKS 배포는 수행하지 않는다.

## 2. Repository 분리 기준

| Environment | Terraform module | 기본 활성화 | 용도 |
| --- | --- | --- | --- |
| dev | module.dev_ecr | enabled | 개발 및 검증 이미지 저장 |
| prod | module.prod_ecr | disabled | 최종 데모 또는 리허설 시점의 운영 후보 이미지 저장 |
| shared | 없음 | 미사용 | ECR은 Shared environment에 두지 않음 |

## 3. Repository 이름 기준

Dev Repository:

| 서비스 | Repository Name | 용도 |
| --- | --- | --- |
| Backend API | moment-dev-backend-api | Dev Backend API 이미지 저장 |
| AI Service | moment-dev-ai-service | Dev AI Service 이미지 저장 |
| Batch Job | moment-dev-batch-job | Dev Batch Job 이미지 저장 |

Prod Repository:

| 서비스 | Repository Name | 용도 |
| --- | --- | --- |
| Backend API | moment-prod-backend-api | Prod Backend API 이미지 저장 |
| AI Service | moment-prod-ai-service | Prod AI Service 이미지 저장 |
| Batch Job | moment-prod-batch-job | Prod Batch Job 이미지 저장 |

기존 공통 이름인 moment-backend-api, moment-ai-service, moment-batch-job은 현재 Dev/Prod 분리 기준과 맞지 않는다.
신규 배포 준비 기준에서는 환경 prefix가 포함된 repository 이름을 사용한다.

## 4. Terraform 구성 기준

Dev ECR은 terraform/environments/dev에서 관리한다.

- module.dev_ecr
- image_tag_mutability = IMMUTABLE
- scan_on_push = true
- encryption_type = AES256

Prod ECR은 terraform/environments/prod에서 관리한다.

- module.prod_ecr
- enable_prod_ecr = false 기본값 유지
- image_tag_mutability = IMMUTABLE
- scan_on_push = true
- encryption_type = AES256

Prod ECR은 비용과 운영 안전성을 위해 기본 비활성화 상태를 유지한다.
최종 데모 또는 리허설 전 별도 승인 후 enable_prod_ecr=true로 사전 생성한다.

## 5. Image tag 정책

이미지 태그는 환경명과 Git commit SHA를 조합하여 사용한다.

| 태그 형식 | 설명 |
| --- | --- |
| dev-{git_sha} | Dev 환경 검증 이미지 |
| prod-{git_sha} | Prod 환경 후보 이미지 |

latest 태그를 기준 배포 태그로 사용하지 않는다.
Git SHA 기반 태그를 사용해 배포 이력 추적과 롤백 기준을 명확히 한다.

## 6. ECR 로그인

    aws ecr get-login-password --region ap-northeast-3 | docker login --username AWS --password-stdin 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com

## 7. Dev 이미지 push 예시

이번 이슈에서는 실제 image push를 수행하지 않는다.
아래 명령은 Dev ECR 생성 이후 수동 검증 또는 향후 CI/CD에서 사용할 예시다.

    BACKEND_TAG=dev-$(git rev-parse --short HEAD)
    docker build -t moment-dev-backend-api:$BACKEND_TAG .
    docker tag moment-dev-backend-api:$BACKEND_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-backend-api:$BACKEND_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-backend-api:$BACKEND_TAG

    AI_TAG=dev-$(git rev-parse --short HEAD)
    docker build -t moment-dev-ai-service:$AI_TAG .
    docker tag moment-dev-ai-service:$AI_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-ai-service:$AI_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-ai-service:$AI_TAG

    BATCH_TAG=dev-$(git rev-parse --short HEAD)
    docker build -t moment-dev-batch-job:$BATCH_TAG .
    docker tag moment-dev-batch-job:$BATCH_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-batch-job:$BATCH_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-batch-job:$BATCH_TAG

## 8. Prod 이미지 push 예시

이번 이슈에서는 Prod ECR 생성과 image push를 수행하지 않는다.
아래 명령은 Prod ECR이 별도 승인 후 생성된 뒤 사용할 수 있는 예시다.

    BACKEND_TAG=prod-$(git rev-parse --short HEAD)
    docker build -t moment-prod-backend-api:$BACKEND_TAG .
    docker tag moment-prod-backend-api:$BACKEND_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-backend-api:$BACKEND_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-backend-api:$BACKEND_TAG

    AI_TAG=prod-$(git rev-parse --short HEAD)
    docker build -t moment-prod-ai-service:$AI_TAG .
    docker tag moment-prod-ai-service:$AI_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-ai-service:$AI_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-ai-service:$AI_TAG

    BATCH_TAG=prod-$(git rev-parse --short HEAD)
    docker build -t moment-prod-batch-job:$BATCH_TAG .
    docker tag moment-prod-batch-job:$BATCH_TAG 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-batch-job:$BATCH_TAG
    docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-prod-batch-job:$BATCH_TAG

## 9. Terraform Output

Dev ECR Repository URL은 다음 output으로 확인한다.

    terraform -chdir=terraform/environments/dev output dev_ecr_repository_urls

Prod ECR Repository URL은 Prod ECR 활성화 후 다음 output으로 확인한다.

    terraform -chdir=terraform/environments/prod output prod_ecr_repository_urls

예상 output key는 다음과 같다.

    backend
    ai-service
    batch

## 10. Lifecycle 정책

ECR lifecycle policy는 terraform/modules/ecr/lifecycle-policy.json을 사용한다.

현재 기준은 다음과 같다.

- untagged image는 1일 후 정리
- v / dev / staging / prod / latest prefix tagged image는 최신 10개만 유지

latest 태그는 배포 기준 태그로 사용하지 않는다.
다만 legacy 또는 수동 검증 과정에서 남은 latest 태그를 정리하기 위해 lifecycle policy prefix에는 포함한다.

## 11. 검증 결과 기준

이번 이슈의 검증 기준은 다음과 같다.

- AWS 계정에 기존 moment ECR Repository가 없는지 확인
- dev/prod/shared Terraform state에 ECR 리소스가 없는지 확인
- Dev ECR target plan에서 6 to add, 0 to change, 0 to destroy 확인
- Prod ECR target plan에서 enable_prod_ecr=true 기준 6 to add, 0 to change, 0 to destroy 확인
- Shared environment에 ECR 생성 module이 없는지 확인
- Terraform validate 통과
- 예상하지 않은 destroy / replacement 없음 확인
- terraform apply 미수행

## 12. 이번 이슈에서 하지 않는 것

- GitHub Actions workflow 생성
- CI/CD 배포 구현
- Docker image build
- Docker image push
- EKS Deployment 수정
- Helm / Kustomize / ArgoCD 수정
- terraform apply
- 기존 ECR Repository 삭제
- 기존 image 삭제
