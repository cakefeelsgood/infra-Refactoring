#!/usr/bin/env bash
set -euo pipefail

REGION="ap-northeast-3"
ACCOUNT_ID="611058323802"
API_DOMAIN="api.moment-team04.click"

printf '\n===== AWS IDENTITY =====\n'
aws sts get-caller-identity --output table

printf '\n===== TERRAFORM STATE - PRESERVED CANDIDATES =====\n'
terraform -chdir=terraform/environments/prod state list \
  | grep -E 'module.edge|route53|cloudfront|waf|acm|ecr|secretsmanager|s3|sqs|iam|openid|data_pipeline|lambda|scheduler' \
  || true

printf '\n===== ECR REPOSITORIES =====\n'
aws ecr describe-repositories \
  --region "$REGION" \
  --repository-names \
    moment-prod-backend-api \
    moment-prod-ai-service \
    moment-prod-batch-job \
  --query 'repositories[].{name:repositoryName,uri:repositoryUri}' \
  --output table

printf '\n===== EXACT PROD ECR IMAGE TAGS =====\n'
for item in \
  "moment-prod-backend-api prod-11d667f" \
  "moment-prod-ai-service prod-19a2a3d" \
  "moment-prod-batch-job prod-11d667f"
do
  repo="$(echo "$item" | awk '{print $1}')"
  tag="$(echo "$item" | awk '{print $2}')"

  echo "----- $repo:$tag -----"
  aws ecr describe-images \
    --region "$REGION" \
    --repository-name "$repo" \
    --image-ids imageTag="$tag" \
    --query 'imageDetails[0].{digest:imageDigest,tags:imageTags,pushedAt:imagePushedAt}' \
    --output json \
    || echo "MISSING_TAG: $repo:$tag"
done

printf '\n===== SECRETS MANAGER - PROD SECRET VERSION STAGES ONLY =====\n'
for secret in \
  moment/prod/backend-api \
  moment/prod/ai-service \
  moment/prod/batch-job \
  moment/prod/public-data/source-config \
  moment/prod/public-data/seoul-openapi \
  moment/prod/public-data/data-go-kr
do
  echo "----- $secret -----"
  aws secretsmanager describe-secret \
    --region "$REGION" \
    --secret-id "$secret" \
    --query '{Name:Name,ARN:ARN,VersionIdsToStages:VersionIdsToStages}' \
    --output json || true
done

printf '\n===== S3 BUCKETS =====\n'
for bucket in \
  moment-prod-raw-data-${ACCOUNT_ID}-${REGION}
do
  echo "----- $bucket -----"
  aws s3api head-bucket --bucket "$bucket" --region "$REGION" && echo "OK: exists" || echo "MISSING: $bucket"
done

printf '\n===== OPTIONAL PROD PROFILE IMAGE BUCKET =====\n'
if terraform -chdir=terraform/environments/prod state list | grep -qE 'module\.prod_profile_image_bucket'; then
  bucket="moment-prod-profile-image-${ACCOUNT_ID}-${REGION}"
  echo "----- $bucket -----"
  aws s3api head-bucket --bucket "$bucket" --region "$REGION" && echo "OK: exists" || echo "MISSING: $bucket"
else
  echo "SKIP: prod profile image bucket is not enabled/tracked in Terraform state"
fi

printf '\n===== SQS MAIN / DLQ =====\n'
for queue in \
  moment-prod-public-data-queue \
  moment-prod-public-data-dlq
do
  echo "----- $queue -----"
  QUEUE_URL="$(aws sqs get-queue-url --region "$REGION" --queue-name "$queue" --query QueueUrl --output text 2>/dev/null || true)"
  if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
    echo "MISSING: $queue"
  else
    echo "$QUEUE_URL"
    aws sqs get-queue-attributes \
      --region "$REGION" \
      --queue-url "$QUEUE_URL" \
      --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed \
      --output table
  fi
done

printf '\n===== CLOUDFRONT / ROUTE53 RUNTIME =====\n'
dig +short "$API_DOMAIN" || true
curl -sS -I "https://${API_DOMAIN}/health" | sed -n '1,30p' || true
