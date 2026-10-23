# M2-NET-05 Network VPC OpenVPN 관리자 접근 경로

## 목적

M2-NET-05는 일반 사용자 트래픽 경로가 아니라 관리자/개발자 접근 경로를 구성하는 작업이다.

관리자 또는 인프라 운영자는 OpenVPN client profile을 AWS Secrets Manager에서 회수한 뒤 OpenVPN으로 Network VPC에 진입하고, Transit Gateway를 통해 Dev 또는 Prod 내부 리소스에 접근한다.

## 관리자 접근 흐름

Developer / Infra Operator
-> MFA + IAM 권한
-> Secrets Manager에서 OpenVPN client profile 회수
-> OpenVPN Client 접속
-> Network VPC Public Subnet OpenVPN EC2
-> Transit Gateway
-> Dev / Prod 내부 리소스

Secrets Manager는 접속용 client profile을 안전하게 배포하기 위한 수단이다.
실제 네트워크 진입 경로는 반드시 OpenVPN을 사용한다.

## 사용자 트래픽과의 분리

사용자 트래픽은 다음 경로를 사용한다.

User
-> Route53
-> CloudFront
-> ALB
-> EKS Service / Pod

관리자 접근 트래픽은 다음 경로를 사용한다.

Admin
-> OpenVPN
-> Network VPC
-> Transit Gateway
-> Dev / Prod

따라서 이 이슈는 M2-EKS-03의 AWS Load Balancer Controller / Ingress 구성이나 M2-EDGE-01의 Route53 / CloudFront / WAF / ACM 구성과 독립적으로 진행할 수 있다.

단, ALB / Ingress / CloudFront 경유 애플리케이션 레벨 검증은 M2-EKS-03 및 M2-EDGE-01 완료 이후 별도 검증한다.

## 구성 방식

이번 구현은 Amazon Linux 2023 기반 EC2에 OpenVPN Community Server를 구성한다.

OpenVPN 인스턴스는 Network VPC Public Subnet에 배치한다.

Network VPC
- Public Subnet
  - NAT Gateway
  - OpenVPN EC2
- TGW Subnet
  - TGW Attachment ENI

## 보안 그룹

OpenVPN 보안 그룹은 Network VPC에 생성한다.

기본 인바운드는 관리자 CIDR에서 OpenVPN 포트만 허용한다.

admin_cidr_blocks
-> UDP 1194
-> OpenVPN EC2

SSH 인바운드는 사용하지 않는다.

## Client Profile 배포

OpenVPN EC2는 부팅 시 user_data에서 server/client 인증서를 생성하고, client profile을 다음 경로에 만든다.

/home/ec2-user/moment-admin.ovpn

생성된 client profile은 EC2 Instance Profile 권한으로 AWS Secrets Manager에 업로드한다.

Terraform output으로 secret 이름과 ARN을 확인할 수 있다.

network_openvpn_client_profile_secret_name
network_openvpn_client_profile_secret_arn

관리자는 IAM/MFA 권한으로 Secrets Manager에서 profile을 회수한다.

aws secretsmanager get-secret-value \
  --region ap-northeast-3 \
  --secret-id <network_openvpn_client_profile_secret_name> \
  --query SecretString \
  --output text > moment-admin.ovpn

## 라우팅

OpenVPN 서버는 VPN client CIDR을 사용한다.

기본값은 다음과 같다.

OpenVPN client CIDR: 10.8.0.0/24
Dev VPC CIDR:        10.20.0.0/16
Prod VPC CIDR:       10.10.0.0/16

OpenVPN 서버는 Dev / Prod CIDR을 클라이언트에게 route push 한다.

또한 OpenVPN EC2는 VPN/NAT 역할을 수행하므로 source_dest_check = false 로 설정한다.

OpenVPN 서버는 Data Tier 관리자 접근 경로에서 VPN client CIDR을 보존하는 routed VPN 방식을 기본으로 사용한다. IP forwarding은 유지하되 Dev / Prod CIDR 대상 MASQUERADE는 기본 비활성화하며, 필요 시 `openvpn_enable_masquerade = true`로 예외 전환한다.

## 민감 정보 관리

다음 파일은 Git에 커밋하면 안 된다.

*.ovpn
*.pem
*.key
*.crt
*.p12

OpenVPN client profile은 Secrets Manager에서 회수하되, Git에 커밋하지 않는다.

## 검증 범위

이번 이슈에서 검증 가능한 항목은 다음과 같다.

- Network VPC Public Subnet에 OpenVPN EC2 생성
- OpenVPN Security Group 생성
- admin_cidr_blocks 기반 OpenVPN 포트 제한
- OpenVPN EC2 source_dest_check 비활성화
- OpenVPN user_data 실행 로그 확인
- OpenVPN server.conf 생성 확인
- client profile Secrets Manager 업로드 확인
- TGW 기반 Dev / Prod CIDR route 구성 확인

M2-EKS-03 / M2-EDGE-01 완료 전에는 다음 검증은 제외한다.

- CloudFront 경유 접근
- Route53 도메인 경유 접근
- ALB Ingress 경유 Backend API 접근
- AWS Load Balancer Controller 기반 Ingress 검증

## 비용 관리

OpenVPN 리소스는 검증 또는 최종 시연 시점에만 생성한다.

기본값은 다음과 같이 비활성화한다.

enable_network_openvpn = false

검증이 필요할 때만 임시로 활성화하고, 캡처 및 테스트가 끝나면 destroy한다.
