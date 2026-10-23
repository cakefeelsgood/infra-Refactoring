# Prod API Stable Origin / ExternalDNS 운영 문서

## 1. 목적

Prod API 도메인 `api.moment-team04.click`의 CloudFront origin이 Kubernetes ALB DNS를 직접 바라보던 구조를 안정화한다.

기존 구조에서는 Backend Ingress 또는 ALB가 재생성될 경우 ALB DNS가 변경되고, CloudFront origin은 이전 ALB DNS를 계속 참조할 수 있었다. 이 경우 `api.moment-team04.click` 요청이 CloudFront 502로 실패할 수 있다.

이를 방지하기 위해 CloudFront는 고정 origin 도메인 `origin-prod-api.moment-team04.click`을 바라보고, ExternalDNS가 Backend Ingress의 현재 ALB 주소를 Route53 origin 레코드로 자동 갱신하도록 구성했다.

## 2. 최종 구조

현재 Prod API 요청 흐름은 다음과 같다.

Frontend
  -> https://api.moment-team04.click
  -> CloudFront
  -> origin-prod-api.moment-team04.click
  -> Prod Backend ALB
  -> backend-api Pods

## 3. 주요 리소스

### 3.1 CloudFront

- Distribution ID: E1D694PL7KHPM0
- CloudFront domain: dg1v72rezsvv5.cloudfront.net
- Viewer domain: api.moment-team04.click
- Origin ID: prod-alb
- Origin domain: origin-prod-api.moment-team04.click
- Origin protocol policy: http-only
- Origin HTTP port: 80
- Origin HTTPS port: 443

현재 ALB Ingress가 HTTP 80 listener를 사용하므로 CloudFront origin protocol policy는 http-only로 유지한다. 향후 ALB HTTPS listener와 ACM 인증서를 붙이면 origin protocol policy 변경을 별도 검토한다.

### 3.2 Route53

Hosted zone:

- Zone name: moment-team04.click.
- Zone ID: Z0631201D3SP8VHP95C7

레코드 구조:

- api.moment-team04.click
  - Type: A Alias
  - Target: CloudFront dg1v72rezsvv5.cloudfront.net

- origin-prod-api.moment-team04.click
  - Type: A Alias
  - Target: 현재 Prod Backend ALB
  - Managed by: ExternalDNS

- origin-prod-api.moment-team04.click
  - Type: TXT
  - Purpose: ExternalDNS ownership record
  - Owner: moment-prod

### 3.3 ExternalDNS

ExternalDNS는 Prod Backend Ingress의 annotation을 보고 Route53 origin 레코드를 관리한다.

ArgoCD:

- Application: external-dns-prod
- Project: external-dns
- Namespace: external-dns

Kubernetes:

- ServiceAccount: external-dns/external-dns
- Deployment: external-dns/external-dns

주요 실행 옵션:

- source=ingress
- provider=aws
- aws-zone-type=public
- registry=txt
- txt-owner-id=moment-prod
- policy=upsert-only
- domain-filter=moment-team04.click
- zone-id-filter=Z0631201D3SP8VHP95C7

### 3.4 IRSA

ExternalDNS는 IRSA를 통해 Route53 권한을 얻는다.

IAM Role:

- moment-prod-external-dns-irsa-role

IAM Policy:

- moment-prod-external-dns-route53-policy

Trust 대상:

- system:serviceaccount:external-dns:external-dns

허용 권한:

- route53:ChangeResourceRecordSets
  - Resource: arn:aws:route53:::hostedzone/Z0631201D3SP8VHP95C7

- route53:GetChange
- route53:ListHostedZones
- route53:ListResourceRecordSets
- route53:ListTagsForResource

ChangeResourceRecordSets는 Prod hosted zone으로 제한하고, 조회성 권한만 전역 허용한다.

## 4. GitOps 구성 파일

ExternalDNS 관련 파일:

- gitops/argocd/prod/applications/external-dns-prod.yaml
- gitops/argocd/prod/external-dns-project.yaml
- gitops/argocd/prod/namespaces/external-dns.yaml
- gitops/charts/external-dns/Chart.yaml
- gitops/charts/external-dns/values.yaml
- gitops/charts/external-dns/templates/deployment.yaml
- gitops/charts/external-dns/templates/rbac.yaml
- gitops/charts/external-dns/templates/serviceaccount.yaml
- gitops/values/prod/external-dns-values.yaml

Backend Ingress annotation:

- gitops/values/prod/backend-api-values.yaml

필수 annotation:

- external-dns.alpha.kubernetes.io/hostname: origin-prod-api.moment-team04.click

## 5. Terraform 구성 파일

Prod CloudFront stable origin / ExternalDNS IRSA 관련 파일:

- terraform/environments/prod/edge-origin-locals.tf
- terraform/environments/prod/external-dns-irsa.tf
- terraform/environments/prod/main.tf
- terraform/environments/prod/outputs.tf
- terraform/environments/prod/variables.tf
- terraform/environments/prod/terraform.tfvars.example

핵심 변수:

- enable_prod_external_dns
- prod_external_dns_namespace
- prod_external_dns_service_account_name
- prod_external_dns_hosted_zone_name
- prod_external_dns_hosted_zone_id
- prod_api_origin_domain_name

주의:

- terraform/environments/prod/terraform.tfvars는 gitignore 대상이다.
- 실제 Prod CloudFront origin을 stable origin으로 유지하려면 로컬 또는 운영 tfvars에 다음 값이 반드시 유지되어야 한다.

prod_api_origin_domain_name = "origin-prod-api.moment-team04.click"

이 값이 비면 local fallback에 의해 prod_alb_dns_name을 다시 참조할 수 있고, 이후 plan에서 CloudFront origin이 ALB 직접 DNS로 되돌아가는 변경이 나타날 수 있다.

## 6. 배포 순서

처음 구성할 때는 다음 순서로 진행한다.

1. ExternalDNS IRSA Terraform plan
2. ExternalDNS IRSA Terraform apply
3. GitOps 코드 merge
4. external-dns-prod ArgoCD Application 생성 및 sync
5. backend-api-prod sync로 Ingress annotation 반영
6. Route53에 origin-prod-api.moment-team04.click A Alias 생성 확인
7. prod_api_origin_domain_name 값을 origin-prod-api.moment-team04.click로 설정
8. CloudFront origin switch Terraform plan
9. CloudFront origin switch Terraform apply
10. API health 및 drift 검증

CloudFront origin을 stable origin으로 전환하기 전에 반드시 Route53 origin A Alias가 생성되어 있어야 한다.

## 7. 검증 명령어

### 7.1 CloudFront origin 확인

aws cloudfront get-distribution \
  --id E1D694PL7KHPM0 \
  --query 'Distribution.{Status:Status,DomainName:DomainName,Origins:DistributionConfig.Origins.Items[].{Id:Id,DomainName:DomainName,OriginProtocolPolicy:CustomOriginConfig.OriginProtocolPolicy,HTTPPort:CustomOriginConfig.HTTPPort,HTTPSPort:CustomOriginConfig.HTTPSPort}}' \
  --output json | jq '.'

정상 기준:

- Status = Deployed
- Origin DomainName = origin-prod-api.moment-team04.click
- OriginProtocolPolicy = http-only
- HTTPPort = 80

### 7.2 Route53 record 확인

aws route53 list-resource-record-sets \
  --hosted-zone-id Z0631201D3SP8VHP95C7 \
  --query 'ResourceRecordSets[?Name==`api.moment-team04.click.` || Name==`origin-prod-api.moment-team04.click.`]' \
  --output json | jq '.'

정상 기준:

- api.moment-team04.click A Alias가 CloudFront를 가리킨다.
- origin-prod-api.moment-team04.click A Alias가 현재 Prod ALB를 가리킨다.
- origin-prod-api.moment-team04.click TXT record가 존재한다.
- TXT record owner가 moment-prod이다.

### 7.3 ArgoCD 상태 확인

kubectl -n argocd get app external-dns-prod -o wide
kubectl -n argocd get app backend-api-prod -o wide

정상 기준:

- external-dns-prod = Synced / Healthy
- backend-api-prod = Synced / Healthy

### 7.4 Runtime 확인

kubectl -n external-dns get pods -o wide
kubectl -n moment-prod get pods -o wide
kubectl -n moment-prod get ingress backend-api -o wide

kubectl -n moment-prod get ingress backend-api \
  -o jsonpath='{.metadata.annotations.external-dns\.alpha\.kubernetes\.io/hostname}{"\n"}'

kubectl -n moment-prod get ingress backend-api \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'

정상 기준:

- external-dns Pod = 1/1 Running
- backend-api Pod = 2개 이상 Running
- Ingress annotation = origin-prod-api.moment-team04.click
- Ingress ADDRESS = 현재 Prod ALB DNS

### 7.5 Health check

curl -i --max-time 20 https://api.moment-team04.click/health

curl -i --max-time 20 https://dg1v72rezsvv5.cloudfront.net/health

정상 기준:

- HTTP/2 200
- 응답 body: MoMent backend is running
- via header에 CloudFront가 표시된다.

### 7.6 Terraform drift 확인

terraform -chdir=terraform/environments/prod plan

정상 기준:

- No changes. Your infrastructure matches the configuration.

## 8. 장애 대응

### 8.1 api.moment-team04.click에서 502 발생

확인 순서:

1. CloudFront origin이 origin-prod-api.moment-team04.click인지 확인한다.
2. origin-prod-api.moment-team04.click Route53 A Alias가 현재 Backend Ingress ALB를 가리키는지 확인한다.
3. Backend Ingress annotation이 유지되는지 확인한다.
4. external-dns-prod가 Synced / Healthy인지 확인한다.
5. external-dns Pod 로그에 AccessDenied 또는 AWS API 오류가 있는지 확인한다.
6. backend-api-prod가 Synced / Healthy인지 확인한다.
7. backend-api Pod와 Ingress target health를 확인한다.
8. Terraform drift가 있는지 확인한다.

### 8.2 origin-prod-api 레코드가 사라진 경우

확인 순서:

1. Backend Ingress annotation 확인
2. external-dns Pod 상태 확인
3. external-dns 로그 확인
4. IRSA role annotation 확인
5. Route53 권한 확인
6. ArgoCD sync 상태 확인

임시 수동 Route53 수정은 최종 해결책으로 보지 않는다. 긴급 복구가 필요하면 수동 조치를 별도 기록하고, 최종적으로는 GitOps 또는 Terraform 정합성으로 되돌린다.

### 8.3 ALB가 재생성된 경우

정상 기대 동작:

1. Backend Ingress status.loadBalancer.ingress hostname이 새 ALB DNS로 변경된다.
2. ExternalDNS가 origin-prod-api.moment-team04.click A Alias를 새 ALB로 upsert한다.
3. CloudFront는 origin-prod-api.moment-team04.click만 계속 바라본다.
4. Frontend의 API base URL은 변경하지 않는다.

검증:

aws route53 list-resource-record-sets \
  --hosted-zone-id Z0631201D3SP8VHP95C7 \
  --query 'ResourceRecordSets[?Name==`origin-prod-api.moment-team04.click.`]' \
  --output json | jq '.'

kubectl -n moment-prod get ingress backend-api -o wide

두 값의 ALB DNS가 같아야 한다.

## 9. 최종 검증 결과

최종 검증 시점 기준 확인 결과:

- CloudFront Status = Deployed
- CloudFront origin = origin-prod-api.moment-team04.click
- api.moment-team04.click A Alias = CloudFront
- origin-prod-api.moment-team04.click A Alias = 현재 Prod ALB
- origin-prod-api.moment-team04.click TXT ownership = external-dns / moment-prod
- external-dns-prod = Synced / Healthy
- backend-api-prod = Synced / Healthy
- external-dns Pod = 1/1 Running
- backend-api Pods = Running
- api.moment-team04.click/health = HTTP/2 200
- CloudFront domain /health = HTTP/2 200
- Terraform drift check = No changes

## 10. 운영 주의사항

- Frontend API base URL은 https://api.moment-team04.click을 사용한다.
- Frontend에서 ALB DNS나 origin-prod-api 도메인을 직접 사용하지 않는다.
- CloudFront origin은 ALB 직접 DNS가 아니라 origin-prod-api.moment-team04.click을 사용한다.
- ExternalDNS가 관리하는 origin-prod-api 레코드를 수동으로 장기 관리하지 않는다.
- terraform/environments/prod/terraform.tfvars의 prod_api_origin_domain_name 값이 운영 환경에서 유지되는지 확인한다.
- tmp 디렉터리의 검증 로그는 커밋 대상이 아니다.
