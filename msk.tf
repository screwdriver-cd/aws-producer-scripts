locals {
  create_vpc = var.vpc_id != null ? true : false
}

data "aws_vpc" "selected" {
  count = local.create_vpc ? 0 : 1

  id              = var.vpc_id
  private_subnets = var.private_subnets
}

locals {
  vpc = (
    local.create_vpc ?
    {
      id              = module.vpc.vpc_id
      cidr_block      = module.vpc.cidr_block
      private_subnets = module.vpc.private_subnets
    } :
    {
      id              = data.aws_vpc.selected.id
      cidr_block      = data.aws_vpc.selected.cidr_block
      private_subnets = data.aws_vpc.selected.private_subnets
    }
  )
}
module "msk_service_sg" {
  depends_on = [local.vpc.private_subnets, local.vpc.id]
  source     = "terraform-aws-modules/security-group/aws"

  name        = "${var.msk_cluster_name}-sg"
  description = "Security group for ${var.msk_cluster_name}-sg with custom ports open within VPC"
  vpc_id      = local.vpc.id

  computed_ingress_with_cidr_blocks = [{
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    description = "MSK-Client port"
    cidr_blocks = local.vpc.vpc_cidr_block
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

  egress_rules = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

data "aws_kms_key" "sd_kms_mk" {
  key_id = "alias/${var.msk_cluster_name}-key"
}

resource "aws_cloudwatch_log_group" "msk_broker_logs" {
  name              = var.msk_cluster_name
  tags              = var.tags
  retention_in_days = 90
  kms_key_id        = data.aws_kms_key.sd_kms_mk.arn
}

resource "aws_msk_cluster" "sd_msk_cluster" {
  depends_on             = [local.vpc.private_subnets, module.vpc, module.msk_service_sg]
  cluster_name           = var.msk_cluster_name
  kafka_version          = "2.6.2"
  number_of_broker_nodes = var.msk_nodes_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    ebs_volume_size = var.msk_ebs_vol
    client_subnets = [
      local.vpc.private_subnets[0],
      local.vpc.private_subnets[1],
      local.vpc.private_subnets[2]
    ]
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

  tags = var.tags
}

#msk secret will be created manually
data "aws_secretsmanager_secret" "sd_msk_secret" {
  name = var.msk_secret_name
}

resource "aws_msk_scram_secret_association" "sd_msk_cluster_secret_association" {
  count           = data.aws_secretsmanager_secret.sd_msk_secret.arn ? 1 : 0
  cluster_arn     = aws_msk_cluster.sd_msk_cluster.arn
  secret_arn_list = [data.aws_secretsmanager_secret.sd_msk_secret.arn]
}

resource "aws_secretsmanager_secret_policy" "sd_msk_secret_policy" {
  count      = data.aws_secretsmanager_secret.sd_msk_secret.arn ? 1 : 0
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
PROPERTIES
}

data "aws_subnet" "privatesubnets" {
  for_each = local.vpc.private_subnets
  id       = each.value
}
locals {
  subnet_cidr_blocks = [for s in data.aws_subnet.privatesubnets : s.cidr_block]
  subnets_ids        = toset(local.vpc.private_subnets)
}

module "endpoint" {
  for_each       = toset(split(",", aws_msk_cluster.sd_msk_cluster.bootstrap_brokers_sasl_scram))
  depends_on     = [aws_msk_cluster.sd_msk_cluster]
  source         = "./modules/endpoint"
  name           = "${substr(each.key, 0, 3)}-${var.msk-name}"
  port           = tonumber(split(":", each.key)[1])
  hostname       = split(":", each.key)[0]
  broker_id      = substr(each.key, 0, 3)
  subnet_mapping = private_subnet_mapping
  vpc_id         = local.vpc.id
  tags           = var.tags
  dynamic "private_subnet_mapping" {
    for_each = zipmap(local.subnet_ids, local.subnet_cidr_blocks)
    content {
      id   = private_subnet_mapping.key
      cidr = private_subnet_mapping.value
    }
  }
}
