#b-1.exampleClusterName.abcde.c2.kafka.us-east-1.amazonaws.com:9098

variable "name" {}
variable "port" {}
variable "hostname" {}
variable "subnet_mapping" { type = map(string) }
variable "vpc_id" {}
variable "tags" {}
variable "broker_id" {}
data "dns_a_record_set" "bootstrap_ip" {
  host = var.hostname
}

module "msk_nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"
  name    = "${var.name}-nlb"

  load_balancer_type = "network"
  internal           = true

  vpc_id = var.vpc_id
  #subnets = [ lookup(var.subnets, var.broker_id)]
  dynamic "subnets" {
    for_each      = var.subnet_mapping
    broker_ip     = data.dns_a_record_set.bootstrap_ip.addrs[0]
    broker_netnum = split(".", broker_ip)[3]
    cidr_netnum   = split("/", split(".", subnets.cidr)[3])[0]
    hostnum       = broker_netnum - cidr_netnum
    cidr          = try(cidrhost(s.cidr, hostnum), null)
    content       = cidr != null ? [lookup(var.subnet_mapping, cidr)] : []
  }

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

  tags = tomap("${var.tags}")
}

resource "aws_vpc_endpoint_service" "sd_vpc_ep_svc" {
  acceptance_required        = true
  network_load_balancer_arns = ["${module.msk_nlb.lb_arn}"]
  tags = merge(tomap("${var.tags}"),
    { "NAME" = "${var.name}-ep-svc" }
  )
}
