# Profile Image Bucket 구성 기준

## 1. 목적

M1-BE-26에서 구현한 프로필 이미지 Presigned URL API가 사용할 S3 Bucket 기준을 정리한다.

프로필 이미지는 사용자 업로드 데이터이며, 공공데이터 파이프라인 Raw Bucket과 목적이 다르다.

따라서 다음 원칙을 따른다.

- 공공데이터 Raw Bucket을 프로필 이미지 저장소로 재사용하지 않는다.
- 프로필 이미지는 별도 S3 Bucket에 저장한다.
- Backend API는 `uploads/profile/*` prefix에 대해서만 업로드 권한을 가진다.
- Dev는 기능 검증을 위해 기본 활성화한다.
- Prod는 비용 운영 기준에 맞게 enable flag로 선택 활성화한다.

## 2. Backend 연동 환경변수

M1-BE-26 Backend API는 다음 환경변수를 사용한다.

| 환경변수 | 설명 | 기본 기준 |
| --- | --- | --- |
| PROFILE_IMAGE_BUCKET_NAME | 프로필 이미지 Bucket 이름 | Terraform output |
| PROFILE_IMAGE_PUBLIC_URL_BASE | 업로드 후 응답에 사용할 URL base | CloudFront URL 권장, CloudFront 연결 전에는 S3 regional URL 형식만 임시 사용 |
| PROFILE_IMAGE_PRESIGNED_URL_EXPIRATION_SECONDS | Presigned URL 만료 시간 | 600 |
| PROFILE_IMAGE_MAX_FILE_SIZE_BYTES | 클라이언트 업로드 전 파일 크기 검증 기준 | 5242880 |
| PROFILE_IMAGE_KEY_PREFIX | 객체 key prefix | uploads/profile |

## 3. Terraform 구성

Profile Image Bucket은 `terraform/modules/profile-image-bucket` 모듈에서 관리한다.

Dev 환경은 `module.dev_profile_image_bucket`을 사용한다.

Prod 환경은 `module.prod_profile_image_bucket`을 사용한다.

기본 naming convention은 다음과 같다.

| Environment | 기본 Bucket 이름 |
| --- | --- |
| dev | moment-dev-profile-image-{account_id}-{region} |
| prod | moment-prod-profile-image-{account_id}-{region} |

## 4. IAM 연결 기준

Backend API Pod용 IAM policy에 profile image bucket 업로드 권한을 optional로 추가한다.

권한 범위는 다음 prefix로 제한한다.

- uploads/profile/*

필요 권한은 다음과 같다.

- s3:PutObject
- s3:AbortMultipartUpload

Raw Bucket 권한, Lambda Collector 권한, Batch Job 권한과 섞지 않는다.

## 5. CORS 기준

브라우저 또는 모바일 클라이언트가 Presigned PUT URL로 직접 업로드할 수 있도록 CORS를 구성한다.

Dev에서는 검증 편의상 wildcard origin을 사용할 수 있으나, Prod에서는 실제 도메인 또는 앱 기준으로 제한한다.

기본 허용 기준은 다음과 같다.

- Method: PUT
- Header: Content-Type, x-amz-*
- Expose Header: ETag

## 6. 주의사항

- S3 Bucket에는 `prevent_destroy = true`가 적용되어 있으므로 삭제 또는 이름 변경은 별도 이슈에서 검토한다.
- Presigned PUT URL만으로 파일 크기를 완전한 서버사이드 정책으로 강제하지 않는다.
- Backend는 `maxFileSizeBytes`를 응답으로 내려주며, 클라이언트는 업로드 전 파일 크기를 검증해야 한다.
- 서버사이드 파일 크기 강제가 필요하면 Presigned POST policy 또는 업로드 후 검증/삭제 정책을 후속으로 검토한다.
- 실제 런타임 업로드 검증은 Backend 환경변수, S3 Bucket, CORS, Backend IRSA 권한이 연결된 뒤 수행한다.
- S3 regional URL은 URL 형식 확인용이며, 실제 사용자 이미지 조회는 CloudFront 등 별도 배포 계층 연결 후 확정한다.

## 공개 읽기 정책

현재 Backend는 프로필 이미지 업로드 후 `public_url_base + objectKey` 형태의 S3 URL을 `fileUrl`로 내려준다.

따라서 앱에서 해당 URL을 직접 렌더링하려면 `uploads/profile/*` prefix에 한해 `s3:GetObject` 공개 읽기가 필요하다.

- 업로드 권한인 `s3:PutObject`는 공개하지 않는다.
- 업로드는 Backend가 발급한 Presigned PUT URL로만 수행한다.
- 공개 읽기는 `public_read_enabled` 옵션으로 제어한다.
- Dev는 로컬/앱 검증을 위해 기본 활성화한다.
- Prod는 CloudFront + OAC 또는 Presigned GET 전환 전까지 기본 비활성화한다.
