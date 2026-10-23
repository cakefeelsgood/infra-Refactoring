# AWS Load Balancer Controller

## 1. 개요

AWS Load Balancer Controller는 Kubernetes Ingress / Service 리소스를 감시하여 AWS ALB, Listener, Rule, Target Group을 자동으로 생성하고 관리하는 제어 컴포넌트다.

사용자 트래픽을 직접 처리하는 것이 아니라, Kubernetes 리소스 변화를 감지하여 AWS 리소스를 프로비저닝하는 역할을 한다.

---

## 2. 구성 요소

| 구성 요소 | 설명 |
|---|---|
| AWS Load Balancer Controller | kube-system 네임스페이스에 Deployment로 설치 |
| IRSA Role | Controller Pod가 AWS API를 호출할 수 있도록 IAM 권한 부여 |
| IngressClass | `alb` IngressClass를 통해 ALB 기반 Ingress 처리 |
| IAM Policy | ALB, Target Group, Security Group 생성/관리 권한 |

---

## 3. Dev 환경 설치 방법

### 3.1 사전 조건

- Dev EKS Cluster ACTIVE 상태
- OIDC Provider 연결 완료
- IAM Policy 생성 완료 (`moment-dev-aws-load-balancer-controller-policy`)

### 3.2 IRSA Role 생성

```bash
# OIDC URL 확인
OIDC_URL=$(aws eks describe-cluster \
  --name moment-dev-eks-cluster \
  --region ap-northeast-3 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

# Trust Policy 파일 생성
cat > ~/alb-trust-policy.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::611058323802:oidc-provider/${OIDC_URL}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com",
          "${OIDC_URL}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
TRUST

# Role 생성
aws iam create-role \
  --role-name moment-dev-alb-controller-irsa-role \
  --assume-role-policy-document file://~/alb-trust-policy.json

# Policy 연결
aws iam attach-role-policy \
  --role-name moment-dev-alb-controller-irsa-role \
  --policy-arn arn:aws:iam::611058323802:policy/moment-dev-aws-load-balancer-controller-policy
```

### 3.3 Helm 설치

```bash
# Helm repo 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# ALB Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=moment-dev-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::611058323802:role/moment-dev-alb-controller-irsa-role \
  --set region=ap-northeast-3 \
  --set vpcId=vpc-03a0d4dcb2dd66af8
```

### 3.4 설치 확인

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system | grep aws-load-balancer
kubectl get ingressclass
```

---

## 4. Dev 검증 절차

### 4.1 테스트 앱 배포

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: default
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test
  namespace: default
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/subnets: subnet-0eb9fb2945e09cb86,subnet-0f8afe6140e2acbae
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-test
            port:
              number: 80
```

### 4.2 검증 확인 명령어

```bash
# Ingress 및 ALB 주소 확인
kubectl get ingress nginx-test

# Target Group Healthy 확인
TG_ARN=$(aws elbv2 describe-target-groups \
  --region ap-northeast-3 \
  --query "TargetGroups[?contains(TargetGroupName,'k8s')].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --region ap-northeast-3 \
  --target-group-arn $TG_ARN \
  --query "TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,State:TargetHealth.State}" \
  --output table

# HTTP 응답 확인
curl -I http://<ALB_DNS>
```

### 4.3 검증 완료 기준

| 항목 | 확인 방법 | 기대 결과 |
|---|---|---|
| ALB Controller Pod | `kubectl get pods -n kube-system` | `Running` |
| IngressClass | `kubectl get ingressclass` | `alb` 확인 |
| ALB 자동 생성 | `kubectl get ingress` | ADDRESS 자동 할당 |
| ALB Scheme | AWS 콘솔 또는 CLI | `internet-facing` |
| Public Subnet 배치 | AWS 콘솔 또는 CLI | Dev Public Subnet 확인 |
| Target Group | AWS 콘솔 또는 CLI | IP mode |
| Target Group Health | CLI | `healthy` |
| HTTP 응답 | curl | `200 OK` |

---

## 5. Prod ALB / Ingress 활성화 정책

### 5.1 기본 정책

Prod ALB / Ingress는 기본 `terraform apply`에서 생성되지 않는다.

현재 Terraform 변수 기본값은 다음과 같다.

```hcl
enable_prod_eks        = false
enable_prod_nodegroups = false
```

Prod 환경은 EKS 자체가 비활성화되어 있으므로 ALB / Ingress도 생성되지 않는다.

### 5.2 Prod 활성화 절차

최종 시연 또는 운영 리허설 기간에만 아래 절차로 활성화한다.

```hcl
# terraform.tfvars
enable_prod_eks        = true
enable_prod_nodegroups = true
```

```bash
terraform plan
terraform apply
```

Prod ALB Controller는 Dev와 동일한 방식으로 설치하되, 아래 값을 Prod 기준으로 변경한다.

| 항목 | Dev | Prod |
|---|---|---|
| cluster name | `moment-dev-eks-cluster` | `moment-prod-eks-cluster` |
| vpcId | `vpc-03a0d4dcb2dd66af8` | `vpc-07bd8a0087908d5c8` |
| subnets | Dev Public Subnet | Prod Public Subnet |
| IRSA Role | `moment-dev-alb-controller-irsa-role` | `moment-prod-alb-controller-irsa-role` |

### 5.3 종료 후 처리

시연 또는 리허설 종료 후 Prod 환경을 비활성화한다.

```hcl
enable_prod_eks        = false
enable_prod_nodegroups = false
```

```bash
terraform plan
terraform apply
```

---

## 6. 비용 절감 운영 방침

MoMent 프로젝트는 비용 절감을 위해 아침에 생성하고 저녁에 destroy하는 방식으로 운영한다.

매일 아침 재생성 시 다음 순서로 진행한다.

```bash
# 1. AWS 인증 확인
aws sts get-caller-identity

# 2. EKS 재생성
cd terraform/environments/dev
terraform apply

# 3. kubeconfig 갱신
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster

# 4. EKS Public Access IP 업데이트 (IP 변경 시)
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws eks update-cluster-config \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster \
  --resources-vpc-config \
    endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="${MY_IP}/32"

# 5. ALB Controller IRSA Role 재생성 (destroy 후)
# docs/alb-controller.md 3.2 절차 참고

# 6. ALB Controller Helm 재설치
# docs/alb-controller.md 3.3 절차 참고
```

매일 저녁 destroy 시 다음 순서로 진행한다.

```bash
# 테스트 리소스 정리
kubectl delete ingress --all
kubectl delete svc --all -l app=nginx-test
kubectl delete deployment --all -l app=nginx-test

# EKS destroy
cd terraform/environments/dev
terraform destroy
```
