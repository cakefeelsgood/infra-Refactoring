# IAM / OIDC / IRSA 권한 구조

## 개요

MoMent 인프라는 장기 Access Key 사용을 피하고, GitHub Actions와 EKS Workload가 IAM Role을 Assume하는 구조를 기준으로 한다.

이번 M2-IAM-01 작업에서는 다음 권한 구조를 구성한다.

- GitHub Actions OIDC 기반 배포 Role
- EKS Cluster IAM Role
- EKS Managed NodeGroup IAM Role
- AWS Load Balancer Controller IAM Policy
- Backend API Pod용 IAM Policy
- Batch Job Pod용 IAM Policy
- AI Service Pod용 IAM Policy
- Lambda Collector IAM Role
- EKS OIDC Provider 및 IRSA Role 조건부 생성 구조

## GitHub Actions OIDC

현재 AWS 계정에는 token.actions.githubusercontent.com OIDC Provider가 이미 존재한다.

해당 Provider는 계정 단위로 재사용하고, MoMent Terraform에서는 새로 생성하지 않는다.

MoMent에서 새로 생성하는 것은 GitHub Actions용 IAM Role이다.

Trust Policy는 다음 조건으로 제한한다.

- aud: sts.amazonaws.com
- sub: repo:Team-msp-architect-2026/msp-team04-infra:ref:refs/heads/develop

즉, MoMent infra repository의 develop branch에서 실행되는 GitHub Actions만 Role을 Assume할 수 있다.

## EKS OIDC / IRSA

현재 ap-northeast-3 리전에 MoMent EKS Cluster가 아직 없으므로 EKS OIDC Provider와 IRSA Role은 기본값으로 생성하지 않는다.

현재 설정은 다음과 같다.

- create_eks_oidc_provider = false
- enable_irsa_roles = false

M2-EKS-01에서 EKS Cluster가 생성된 후, EKS OIDC issuer URL을 확인하고 IAM module에 연결한다.

EKS OIDC issuer URL 확인 예시는 다음과 같다.

aws eks describe-cluster --name <cluster-name> --region ap-northeast-3 --query "cluster.identity.oidc.issuer" --output text

EKS OIDC Provider가 준비되면 다음 값을 활성화한다.

- create_eks_oidc_provider = true
- eks_oidc_issuer_url = <EKS OIDC issuer URL>
- enable_irsa_roles = true

## ServiceAccount Annotation 기준

IRSA가 활성화되면 Kubernetes ServiceAccount에는 다음 annotation을 추가한다.

예시:

apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-api
  namespace: moment
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/moment-dev-backend-irsa-role

## ServiceAccount 매핑

| Workload | Namespace | ServiceAccount | IAM Role |
| --- | --- | --- | --- |
| AWS Load Balancer Controller | kube-system | aws-load-balancer-controller | moment-dev-aws-load-balancer-controller-irsa-role |
| Backend API | moment | backend-api | moment-dev-backend-irsa-role |
| Batch Job | moment | batch-job | moment-dev-batch-irsa-role |
| AI Service | moment | ai-service | moment-dev-ai-service-irsa-role |

## 권한 분리 기준

| 대상 | 권한 |
| --- | --- |
| GitHub Actions | ECR Push / Pull |
| EKS Cluster | AmazonEKSClusterPolicy |
| EKS NodeGroup | AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly |
| AWS Load Balancer Controller | ALB, Listener, TargetGroup, SecurityGroup 관리 |
| Backend API Pod | Secrets Manager Read, CloudWatch Logs Write |
| Batch Job Pod | S3 Raw Bucket Access, SQS Consume, CloudWatch Logs Write |
| AI Service Pod | Secrets Manager Read, OpenSearch Access, CloudWatch Logs Write |
| Lambda Collector | S3 Raw Bucket Access, SQS Send, CloudWatch Logs Write |

## 후속 작업

- M2-EKS-01에서 EKS Cluster 생성 후 EKS OIDC issuer URL을 연결한다.
- AWS Load Balancer Controller 설치 시 ServiceAccount에 IRSA annotation을 적용한다.
- SQS 모듈을 통해 생성된 Main Queue ARN을 Batch / Lambda Role에 연결한다.
- OpenSearch 모듈 생성 후 AI Service Role에 OpenSearch Domain ARN을 연결한다.
