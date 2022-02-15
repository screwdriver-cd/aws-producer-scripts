locals {
  create_vpc = var.vpc_id != null ? false : true
}

data "aws_vpc" "selected" {
  count = local.create_vpc ? 0 : 1
  id    = var.vpc_id
}

data "aws_subnet" "selected" {
  for_each = local.create_vpc ? [] : toset(var.private_subnets)
  vpc_id = var.vpc_id
  cidr_block = each.value
}

locals {
  vpc = (
    local.create_vpc ?
    {
      id              = module.vpc.vpc_id
      cidr_block      = module.vpc.vpc_cidr_block
      private_subnets = module.vpc.private_subnets
    } :
    {
      id              = data.aws_vpc.selected[0].id
      cidr_block      = data.aws_vpc.selected[0].cidr_block
      private_subnets = [for s in data.aws_subnet.selected : s.id]
    }
  ) 
}

module "msk_service_sg" {
  depends_on = [local.vpc]
  source     = "terraform-aws-modules/security-group/aws"

  name        = "${var.msk_cluster_name}-sg"
  description = "Security group for ${var.msk_cluster_name}-sg with custom ports open within VPC"
  vpc_id      = local.vpc.id

  computed_ingress_with_cidr_blocks = [{
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    description = "MSK-Client port"
    cidr_blocks = local.vpc.cidr_block
  }]
  number_of_computed_ingress_with_cidr_blocks = 1
  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 9096
      to_port                  = 9096
      protocol                 = "tcp"
      description              = "MSK-Client port"
      source_security_group_id = module.msk_service_sg.security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

data "aws_kms_key" "sd_kms_mk" {
  key_id = "alias/${var.kms_key_alias_name}"
}

resource "aws_cloudwatch_log_group" "msk_broker_logs" {
  name              = var.msk_cluster_name
  tags              = var.tags
  retention_in_days = 7
  kms_key_id        = data.aws_kms_key.sd_kms_mk.arn
}

resource "aws_msk_cluster" "sd_msk_cluster" {
  depends_on             = [local.vpc, module.msk_service_sg]
  cluster_name           = var.msk_cluster_name
  kafka_version          = "2.6.2"
  number_of_broker_nodes = length(local.vpc.private_subnets)

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    ebs_volume_size = var.msk_ebs_vol
    client_subnets = [ for i in local.vpc.private_subnets: i ]
    security_groups = [module.msk_service_sg.security_group_id]
  }

  client_authentication {
    sasl {
      scram = true
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = data.aws_kms_key.sd_kms_mk.arn
    encryption_in_transit {
      in_cluster    = true
      client_broker = "TLS"
    }
  }


  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_broker_logs.name
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.sd_msk_config.arn
    revision = aws_msk_configuration.sd_msk_config.latest_revision
  }

  tags = var.tags
}

#msk secret will be created manually
data "aws_secretsmanager_secret" "sd_msk_secret" {
  name = var.msk_secret_name
}

resource "aws_msk_scram_secret_association" "sd_msk_cluster_secret_association" {
  count           = data.aws_secretsmanager_secret.sd_msk_secret.arn != null ? 1 : 0
  cluster_arn     = aws_msk_cluster.sd_msk_cluster.arn
  secret_arn_list = [data.aws_secretsmanager_secret.sd_msk_secret.arn]
}

resource "aws_secretsmanager_secret_policy" "sd_msk_secret_policy" {
  count      = data.aws_secretsmanager_secret.sd_msk_secret.arn != null ? 1 : 0
  depends_on = [module.vpc, module.msk_service_sg]
  secret_arn = data.aws_secretsmanager_secret.sd_msk_secret.arn
  policy     = <<POLICY
{
  "Version" : "2012-10-17",
  "Statement" : [ {
    "Sid": "AWSKafkaResourcePolicy",
    "Effect" : "Allow",
    "Principal" : {
      "Service" : "kafka.amazonaws.com"
    },
    "Action" : "secretsmanager:getSecretValue",
    "Resource" : "${data.aws_secretsmanager_secret.sd_msk_secret.arn}"
  } ]
}
POLICY
}

resource "aws_msk_configuration" "sd_msk_config" {
  depends_on     = [module.vpc, module.msk_service_sg]
  kafka_versions = ["2.6.2"]
  name           = "${var.msk_cluster_name}-config-v1"

  server_properties = <<PROPERTIES
auto.create.topics.enable = false
delete.topic.enable = true
min.insync.replicas = 2
log.retention.hours = 72
num.partitions = 2
PROPERTIES
}

# #                              AFTER CLUSTER CREATION
##*********************************************************************************************#
# # endpoint should be created after the cluster is ready as the source mapping is dynamic
# # for first time creation comment endpoint creation and run apply on cluster first


data "aws_subnet" "privatesubnets" {
  for_each = toset(local.vpc.private_subnets)
  id       = each.value
}
locals {
  private_subnet_mapping = [
    for id, subnet in data.aws_subnet.privatesubnets: {
        id   = id 
        cidr = subnet.cidr_block
        az   = subnet.availability_zone
      }
  ]
}
locals {
  brokers = toset(split(",", aws_msk_cluster.sd_msk_cluster.bootstrap_brokers_sasl_scram))
}


module "endpoint" {
  depends_on     = [aws_msk_cluster.sd_msk_cluster]
  for_each       = local.brokers
  source         = "./modules/endpoint"
  name           = "${substr(each.key, 0, 3)}-${var.msk_cluster_name}"
  port           = tonumber(split(":", each.key)[1])
  hostname       = split(":", each.key)[0]
  broker_id      = substr(each.key, 0, 3)
  subnet_mapping = local.private_subnet_mapping
  vpc_id         = local.vpc.id
  tags           = var.tags
}

#*********************************************************************************************#