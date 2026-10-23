locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.env
    ManagedBy   = "terraform"
    Owner       = "team04"
  }
}

module "dev_ecr" {
  source = "../../modules/ecr"

  repositories = {
    backend = {
      name        = "${var.project_name}-dev-backend-api"
      description = "Backend API container image repository"
    }

    ai-service = {
      name        = "${var.project_name}-dev-ai-service"
      description = "AI Service container image repository"
    }

    batch = {
      name        = "${var.project_name}-dev-batch-job"
      description = "Batch Job container image repository"
    }

    capacity-split-webhook = {
      name        = "${var.project_name}-dev-capacity-split-webhook"
      description = "capacity-split mutating webhook (base on-demand / burst spot) image repository"
    }
  }

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  encryption_type      = "AES256"

  tags = local.common_tags
}

module "dev_vpc" {
  count  = var.enable_dev_vpc ? 1 : 0
  source = "../../modules/dev-vpc"

  project_name     = var.project_name
  env              = "dev"
  eks_cluster_name = var.dev_eks_cluster_name

  vpc_cidr = var.dev_vpc_cidr

  availability_zones = [
    "${var.primary_region}a",
    "${var.primary_region}c"
  ]

  public_subnet_cidrs = [
    "10.20.0.0/24",
    "10.20.1.0/24"
  ]

  private_app_subnet_cidrs = [
    "10.20.10.0/24",
    "10.20.11.0/24"
  ]

  karpenter_node_subnet_cidrs = var.enable_dev_karpenter ? var.dev_karpenter_node_subnet_cidrs : []

  private_data_subnet_cidrs = [
    "10.20.20.0/24",
    "10.20.21.0/24"
  ]

  tgw_subnet_cidrs = [
    "10.20.100.0/28",
    "10.20.100.16/28"
  ]

  transit_gateway_id = null

  tags = local.common_tags
}

module "dev_security_group" {
  count  = var.enable_dev_vpc ? 1 : 0
  source = "../../modules/security-group"

  name_prefix       = "moment-dev"
  environment       = "dev"
  vpc_id            = module.dev_vpc[0].dev_vpc_id
  create_service_sg = true
  create_openvpn_sg = false

  app_port                   = var.app_port
  admin_cidr_blocks          = var.admin_cidr_blocks
  openvpn_client_cidr_blocks = [var.openvpn_vpn_cidr]

  common_tags = {
    Project = "MoMent"
  }

  create_eks_cluster_sg_ingress_rules = var.enable_dev_eks && var.enable_dev_eks_cluster_sg_ingress_rules
  eks_cluster_sg_id                   = var.enable_dev_eks && var.enable_dev_eks_cluster_sg_ingress_rules ? module.dev_eks[0].cluster_security_group_id : ""
}

module "dev_vpc_endpoint" {
  count  = var.enable_dev_vpc && var.enable_dev_vpc_endpoints ? 1 : 0
  source = "../../modules/vpc-endpoint"

  name_prefix = "moment-dev"
  environment = "dev"

  vpc_id                      = module.dev_vpc[0].dev_vpc_id
  private_app_subnet_ids      = module.dev_vpc[0].dev_private_app_subnet_ids
  private_app_route_table_ids = [module.dev_vpc[0].dev_private_app_route_table_id]
  endpoint_security_group_id  = module.dev_security_group[0].vpc_endpoint_sg_id

  common_tags = {
    Project = "MoMent"
  }
}


resource "aws_security_group_rule" "vpc_endpoint_ingress_from_eks_cluster_sg" {
  count = var.enable_dev_vpc && var.enable_dev_vpc_endpoints && var.enable_dev_eks ? 1 : 0

  type                     = "ingress"
  security_group_id        = module.dev_security_group[0].vpc_endpoint_sg_id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.dev_eks[0].cluster_security_group_id

  description = "Allow HTTPS from EKS cluster SG (auto-created) to VPC endpoints"
}

module "dev_sqs" {
  count = var.enable_dev_sqs ? 1 : 0

  source = "../../modules/sqs"

  project_name = var.project_name
  environment  = "dev"

  queue_name = "${var.project_name}-dev-public-data-queue"
  dlq_name   = "${var.project_name}-dev-public-data-dlq"

  visibility_timeout_seconds    = var.dev_sqs_visibility_timeout_seconds
  message_retention_seconds     = var.dev_sqs_message_retention_seconds
  dlq_message_retention_seconds = var.dev_sqs_dlq_message_retention_seconds
  max_receive_count             = var.dev_sqs_max_receive_count
  receive_wait_time_seconds     = var.dev_sqs_receive_wait_time_seconds
  delay_seconds                 = var.dev_sqs_delay_seconds
  max_message_size              = var.dev_sqs_max_message_size
  sqs_managed_sse_enabled       = var.dev_sqs_managed_sse_enabled

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}

module "dev_s3_raw_bucket" {
  count = var.enable_dev_s3_raw_bucket ? 1 : 0

  source = "../../modules/s3"

  project_name = var.project_name
  environment  = "dev"
  bucket_name  = var.dev_raw_bucket_name

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}

module "dev_profile_image_bucket" {
  count = var.enable_dev_profile_image_bucket ? 1 : 0

  source = "../../modules/profile-image-bucket"

  project_name         = var.project_name
  environment          = "dev"
  bucket_name          = var.dev_profile_image_bucket_name
  object_key_prefix    = var.dev_profile_image_object_key_prefix
  cors_allowed_origins = var.dev_profile_image_allowed_origins
  public_read_enabled  = var.dev_profile_image_public_read_enabled

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}

module "dev_notification_sns" {
  count = var.enable_dev_notification_sns ? 1 : 0

  source = "../../modules/notification-sns"

  project_name      = var.project_name
  environment       = "dev"
  topic_name        = var.dev_notification_sns_topic_name
  display_name      = var.dev_notification_sns_display_name
  kms_master_key_id = var.dev_notification_sns_kms_master_key_id

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}



module "dev_iam" {
  count  = var.enable_dev_iam ? 1 : 0
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = "dev"

  github_repository            = var.github_repository
  github_default_branch        = var.github_default_branch
  github_oidc_allowed_subjects = var.github_oidc_allowed_subjects

  create_github_oidc_provider = false
  github_oidc_provider_arn    = var.github_oidc_provider_arn

  # Dev workload IRSA roles are managed by dedicated Dev runtime config blocks
  # such as m3-config-irsa.tf and alb-controller-irsa.tf.
  # Keep the shared IAM module focused on base IAM roles/policies here to avoid
  # duplicate EKS OIDC providers and duplicate IRSA role names during fresh Dev recreate.
  create_eks_oidc_provider = false
  enable_irsa_roles        = false

  ecr_repository_arns = module.dev_ecr.repository_arns

  raw_bucket_access_policy_arn_map = var.enable_dev_s3_raw_bucket ? {
    raw = module.dev_s3_raw_bucket[0].raw_bucket_access_policy_arn
  } : {}

  profile_image_bucket_arns = var.enable_dev_profile_image_bucket ? [
    module.dev_profile_image_bucket[0].bucket_arn
  ] : []
  profile_image_object_key_prefix = var.dev_profile_image_object_key_prefix

  notification_sns_topic_arns = var.enable_dev_notification_sns ? [
    module.dev_notification_sns[0].topic_arn
  ] : []

  sqs_queue_arns                     = var.enable_dev_sqs ? [module.dev_sqs[0].queue_arn] : []
  enable_sqs_queue_policy_statements = var.enable_dev_sqs

  opensearch_domain_arns = var.enable_dev_vpc && var.enable_dev_opensearch ? [
    module.dev_opensearch[0].domain_arn,
    "${module.dev_opensearch[0].domain_arn}/*"
  ] : []

  attach_lambda_raw_bucket_policy              = var.enable_dev_s3_raw_bucket
  enable_lambda_collector_secrets_manager_read = var.enable_lambda_collector_secrets_manager_read

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })

  eks_oidc_issuer_url   = var.eks_oidc_issuer_url
  eks_oidc_provider_arn = var.eks_oidc_provider_arn
  irsa_service_accounts = var.irsa_service_accounts

  depends_on = [
    module.dev_sqs,
    module.dev_s3_raw_bucket,
    module.dev_profile_image_bucket,
    module.dev_notification_sns
  ]
}


module "dev_data_pipeline" {
  count = var.enable_dev_iam && var.enable_dev_data_pipeline && var.enable_dev_sqs && var.enable_dev_s3_raw_bucket ? 1 : 0

  source = "../../modules/data-pipeline"

  project_name = var.project_name
  environment  = "dev"

  lambda_function_name = "${var.project_name}-dev-public-data-collector"
  lambda_role_arn      = module.dev_iam[0].lambda_collector_role_arn

  raw_bucket_name                 = module.dev_s3_raw_bucket[0].raw_bucket_name
  queue_url                       = module.dev_sqs[0].queue_url
  public_data_api_url             = var.data_pipeline_public_data_api_url
  public_data_sources_json        = var.data_pipeline_public_data_sources_json
  public_data_sources_secret_name = var.data_pipeline_public_data_sources_secret_name

  schedule_expression = var.data_pipeline_schedule_expression
  schedule_state      = var.dev_data_pipeline_schedule_state

  lambda_runtime     = var.data_pipeline_lambda_runtime
  lambda_timeout     = var.data_pipeline_lambda_timeout
  lambda_memory_size = var.data_pipeline_lambda_memory_size
  log_retention_days = var.data_pipeline_log_retention_days

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })

  depends_on = [
    module.dev_sqs,
    module.dev_s3_raw_bucket
  ]
}


module "dev_alerting_slack_notifier" {
  count  = var.enable_dev_alerting_slack_notifier ? 1 : 0
  source = "../../modules/alerting-slack-notifier"

  project_name = var.project_name
  environment  = "dev"

  sns_topic_name            = var.dev_alerting_sns_topic_name
  sns_display_name          = "MoMent Dev Monitoring Alert"
  slack_webhook_secret_name = var.dev_alerting_slack_webhook_secret_name

  enable_cloudwatch_alarms = var.enable_dev_cloudwatch_alarms

  rds_instance_identifiers = var.enable_dev_vpc && var.enable_dev_rds ? {
    postgres = module.dev_rds[0].db_instance_identifier
  } : {}

  redis_replication_group_ids = var.enable_dev_vpc && var.enable_dev_redis ? {
    redis = module.dev_redis[0].redis_replication_group_id
  } : {}

  opensearch_domain_names = var.enable_dev_vpc && var.enable_dev_opensearch ? {
    opensearch = module.dev_opensearch[0].domain_name
  } : {}

  sqs_queue_names = var.enable_dev_sqs ? {
    public_data = module.dev_sqs[0].queue_name
  } : {}

  sqs_dlq_names = var.enable_dev_sqs ? {
    public_data = module.dev_sqs[0].dlq_name
  } : {}

  lambda_function_names = (
    var.enable_dev_iam &&
    var.enable_dev_data_pipeline &&
    var.enable_dev_sqs &&
    var.enable_dev_s3_raw_bucket
    ) ? {
    public_data_collector = module.dev_data_pipeline[0].lambda_function_name
  } : {}

  application_load_balancer_tag_selectors = var.dev_alerting_application_load_balancer_tag_selectors
  target_group_tag_selectors              = var.dev_alerting_target_group_tag_selectors

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })

  event_catalog_name_prefix = "moment-dev"

  rds_failover_event_source_ids = [
    "moment-dev-postgres"
  ]
}

module "dev_eks" {
  count = var.enable_dev_vpc && var.enable_dev_iam && var.enable_dev_eks ? 1 : 0

  source = "../../modules/eks"

  project_name = var.project_name
  environment  = "dev"

  cluster_name       = var.dev_eks_cluster_name
  cluster_role_arn   = module.dev_iam[0].eks_cluster_role_arn
  kubernetes_version = var.prod_eks_kubernetes_version

  subnet_ids                 = module.dev_vpc[0].dev_private_app_subnet_ids
  cluster_security_group_ids = []

  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = var.dev_eks_public_access_cidrs

  authentication_mode                         = "API"
  bootstrap_cluster_creator_admin_permissions = true
  cluster_admin_principal_arn                 = var.dev_eks_cluster_admin_principal_arn

  addons = {
    vpc-cni = {
      addon_version        = "v1.21.1-eksbuild.1"
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }

    coredns = {
      addon_version = "v1.13.2-eksbuild.4"
    }

    kube-proxy = {
      addon_version = "v1.35.3-eksbuild.2"
    }

    aws-ebs-csi-driver = {
      addon_version = "v1.60.0-eksbuild.1"
    }
  }

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}

module "dev_eks_nodegroups" {
  count = var.enable_dev_vpc && var.enable_dev_iam && var.enable_dev_eks && var.enable_dev_nodegroups ? 1 : 0

  source = "../../modules/eks-nodegroup"

  project_name = var.project_name
  environment  = "dev"

  cluster_name  = module.dev_eks[0].cluster_name
  node_role_arn = module.dev_iam[0].eks_node_role_arn
  subnet_ids    = module.dev_vpc[0].dev_private_app_subnet_ids

  node_groups = {
    core_on_demand = {
      name           = "${var.project_name}-dev-core-on-demand-ng"
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.medium"]
      min_size       = 1
      desired_size   = 2
      max_size       = 2
      disk_size      = 20

      labels = {
        workload = "core"
        capacity = "on-demand"
      }

      taints = []
    }

    batch_spot = {
      name           = "${var.project_name}-dev-batch-spot-ng"
      capacity_type  = "SPOT"
      instance_types = ["t3.medium"]
      min_size       = 0
      desired_size   = 1
      max_size       = 2
      disk_size      = 20

      labels = {
        workload = "batch"
        capacity = "spot"
      }

      taints = [
        {
          key    = "workload"
          value  = "batch"
          effect = "NO_SCHEDULE"
        },
        {
          key    = "capacity"
          value  = "spot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    ai_spot = {
      name           = "${var.project_name}-dev-ai-spot-ng"
      capacity_type  = "SPOT"
      instance_types = ["t3.medium"]
      min_size       = 0
      desired_size   = 0
      max_size       = 2
      disk_size      = 30

      labels = {
        workload = "ai"
        capacity = "spot"
      }

      taints = [
        {
          key    = "workload"
          value  = "ai"
          effect = "NO_SCHEDULE"
        },
        {
          key    = "capacity"
          value  = "spot"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    ops_on_demand = {
      name           = "${var.project_name}-dev-ops-on-demand-ng"
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.medium"]
      min_size       = 1
      desired_size   = 1
      max_size       = 2
      disk_size      = 20

      labels = {
        workload = "ops"
        capacity = "on-demand"
      }

      taints = [
        {
          key    = "workload"
          value  = "ops"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  common_tags = local.common_tags
}

module "dev_redis" {
  count = var.enable_dev_vpc && var.enable_dev_redis ? 1 : 0

  source = "../../modules/redis"

  project_name = var.project_name
  environment  = "dev"

  replication_group_id = "${var.project_name}-dev-redis"
  description          = "MoMent Dev Redis for distributed lock and recommendation cache"

  subnet_ids         = module.dev_vpc[0].dev_private_data_subnet_ids
  security_group_ids = [module.dev_security_group[0].redis_sg_id]

  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type
  port           = 6379

  automatic_failover_enabled = false
  multi_az_enabled           = false

  common_tags = local.common_tags

  notification_topic_arn = try(module.dev_alerting_slack_notifier[0].sns_topic_arn, null)
}

module "dev_rds" {
  count = var.enable_dev_vpc && var.enable_dev_rds ? 1 : 0

  source = "../../modules/rds"

  project_name = var.project_name
  environment  = "dev"

  identifier      = "${var.project_name}-dev-postgres"
  database_name   = var.rds_database_name
  master_username = var.rds_master_username

  subnet_ids         = module.dev_vpc[0].dev_private_data_subnet_ids
  security_group_ids = [module.dev_security_group[0].rds_sg_id]

  engine_version         = var.rds_engine_version
  parameter_group_family = var.rds_parameter_group_family
  instance_class         = var.dev_rds_instance_class

  allocated_storage     = var.dev_rds_allocated_storage
  max_allocated_storage = var.dev_rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az                = var.dev_rds_multi_az
  backup_retention_period = var.dev_rds_backup_retention_period
  backup_window           = var.dev_rds_backup_window
  maintenance_window      = var.dev_rds_maintenance_window

  deletion_protection       = var.dev_rds_deletion_protection
  skip_final_snapshot       = var.dev_rds_skip_final_snapshot
  final_snapshot_identifier = var.dev_rds_skip_final_snapshot ? null : coalesce(var.dev_rds_final_snapshot_identifier, "${var.project_name}-dev-postgres-final-snapshot")

  common_tags = local.common_tags
}

module "dev_opensearch" {
  count = var.enable_dev_vpc && var.enable_dev_opensearch ? 1 : 0

  source = "../../modules/opensearch"

  project_name = var.project_name
  environment  = "dev"

  domain_name    = "${var.project_name}-dev-opensearch"
  engine_version = var.opensearch_engine_version

  instance_type  = var.dev_opensearch_instance_type
  instance_count = 1

  dedicated_master_enabled      = false
  zone_awareness_enabled        = false
  multi_az_with_standby_enabled = false

  ebs_volume_type = var.opensearch_ebs_volume_type
  ebs_volume_size = var.dev_opensearch_ebs_volume_size

  subnet_ids         = local.dev_opensearch_subnet_ids
  security_group_ids = [module.dev_security_group[0].opensearch_sg_id]

  create_service_linked_role = var.create_opensearch_service_linked_role

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}

locals {
  dev_opensearch_subnet_ids = (
    var.enable_dev_vpc &&
    length(module.dev_vpc) > 0 &&
    length(module.dev_vpc[0].dev_private_data_subnet_ids) > 0
    ) ? slice(
    module.dev_vpc[0].dev_private_data_subnet_ids,
    0,
    1
  ) : []

  dev_runtime_secret_definitions = {
    backend_api = {
      name        = "moment/dev/backend-api"
      description = "MoMent Dev Backend API runtime secrets. Values are managed out-of-band and are not stored in Terraform."
    }
    ai_service = {
      name        = "moment/dev/ai-service"
      description = "MoMent Dev AI Service runtime secrets. Values are managed out-of-band and are not stored in Terraform."
    }
    batch_job = {
      name        = "moment/dev/batch-job"
      description = "MoMent Dev Batch Job runtime secrets. Values are managed out-of-band and are not stored in Terraform."
    }
  }

  dev_public_data_secret_definitions = {
    source_config = {
      name        = "moment/dev/public-data/source-config"
      description = "MoMent Dev public data source config for Lambda Collector. Values are managed out-of-band and are not stored in Terraform."
    }
    seoul_openapi = {
      name        = "moment/dev/public-data/seoul-openapi"
      description = "MoMent Dev Seoul OpenAPI key for public data Lambda Collector. Values are managed out-of-band and are not stored in Terraform."
    }
    data_go_kr = {
      name        = "moment/dev/public-data/data-go-kr"
      description = "MoMent Dev data.go.kr API key for public data Lambda Collector. Values are managed out-of-band and are not stored in Terraform."
    }
  }
}

resource "aws_secretsmanager_secret" "dev_runtime" {
  for_each = var.enable_dev_external_secrets_irsa ? local.dev_runtime_secret_definitions : {}

  name                    = each.value.name
  description             = each.value.description
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = each.value.name
    Role = "runtime-secret"
  })
}


resource "aws_secretsmanager_secret" "dev_public_data" {
  for_each = var.enable_dev_public_data_secrets ? local.dev_public_data_secret_definitions : {}

  name                    = each.value.name
  description             = each.value.description
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = each.value.name
    Role = "public-data-secret"
  })
}

module "dev_external_secrets_irsa" {
  count  = var.enable_dev_external_secrets_irsa && var.enable_dev_iam && var.enable_dev_eks ? 1 : 0
  source = "../../modules/external-secrets-irsa"

  project_name = var.project_name
  environment  = "dev"

  namespace            = var.dev_external_secrets_namespace
  service_account_name = var.dev_external_secrets_service_account_name

  eks_oidc_provider_arn = module.dev_eks[0].eks_oidc_provider_arn
  eks_oidc_provider_url = module.dev_eks[0].eks_oidc_provider_url

  secret_arns = concat(
    [
      for secret in aws_secretsmanager_secret.dev_runtime : secret.arn
    ],
    var.enable_dev_alerting_slack_notifier ? [
      module.dev_alerting_slack_notifier[0].slack_webhook_secret_arn
    ] : []
  )

  allow_rds_managed_secrets = false

  common_tags = local.common_tags
}
