#b-1.exampleClusterName.abcde.c2.kafka.us-east-1.amazonaws.com:9098

variable "name" {}
variable "port" {}
variable "hostname" {}
variable "subnet_mapping" { type = list(map(string)) }
variable "vpc_id" {}
variable "tags" {}
variable "broker_id" {}
data "dns_a_record_set" "bootstrap_ip" {
  host = var.hostname
}

locals {
  broker_ip     = data.dns_a_record_set.bootstrap_ip.addrs[0]
  subnets       =  [ for entry in var.subnet_mapping: entry.id if cidrhost(entry.cidr,0) == 
      cidrhost(format("%s/%s", local.broker_ip, element(split("/", entry.cidr), 1)), 0) 
  ]
}

module "msk_nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"
  name    = "${var.name}-nlb"

  load_balancer_type = "network"
  internal           = true

  vpc_id = var.vpc_id
  subnets = local.subnets

  target_groups = [
    {
      name_prefix      = "${var.broker_id}-tg"
      backend_protocol = "TCP"
      backend_port     = "${var.port}"
      target_type      = "ip"
      targets = [
        {
          target_id = "${data.dns_a_record_set.bootstrap_ip.addrs[0]}"
          port      = "${var.port}"
        },
      ]
    }
  ]
  http_tcp_listeners = [
    {
      port               = "${var.port}"
      protocol           = "TCP"
      target_group_index = 0
    }
  ]

  tags = merge(tomap("${var.tags}"),
    { "Name" = "${var.name}-nlb" }
  )
}

resource "aws_vpc_endpoint_service" "sd_vpc_ep_svc" {
  acceptance_required        = true
  network_load_balancer_arns = ["${module.msk_nlb.lb_arn}"]
  tags = merge(tomap("${var.tags}"),
    { "Name" = "${var.name}-ep-svc" }
  )
}
