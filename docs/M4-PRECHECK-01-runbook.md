# M4-PRECHECK-01 사전 점검 Runbook

## 개요
M4 Observability 작업 시작 전 AWS 인증, kubeconfig, EKS 접근, ArgoCD 접근 가능 여부를 확인한다.

## 사전 조건
- AWS CLI 설치
- kubectl 설치
- helm 설치
- MFA 디바이스 등록된 IAM 계정

## 1. MFA 인증

```bash
aws sts get-session-token \
  --serial-number arn:aws:iam::611058323802:mfa/<YOUR_USERNAME> \
  --token-code <MFA_6자리>

export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

## 2. AWS 인증 확인

```bash
aws sts get-caller-identity
aws eks list-clusters --region ap-northeast-3
```

## 3. Dev EKS kubeconfig 갱신

```bash
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster

kubectl config current-context
```

## 4. EKS 접근 확인

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -A
```

## 5. ArgoCD 접근 확인

```bash
kubectl get pods -n argocd
```

## 6. Helm release 조회

```bash
helm list -A
```

## 트러블슈팅

### AWS token 만료 시
MFA 재인증 필요. 1번 단계 반복.

### kubectl credentials 에러 시
```bash
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster
```

### EKS 접근 거부 시
IAM user가 EKS access entry에 등록됐는지 확인:
```bash
aws eks list-access-entries \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster
```
없으면 추가:
```bash
aws eks create-access-entry \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster \
  --principal-arn arn:aws:iam::611058323802:user/<YOUR_USERNAME>

aws eks associate-access-policy \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster \
  --principal-arn arn:aws:iam::611058323802:user/<YOUR_USERNAME> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### Prod EKS 비활성 상태
Prod EKS는 비용 정책상 M4 기간 중 비활성 상태.
M4 Runtime 검증은 Dev EKS 기준으로 진행.
