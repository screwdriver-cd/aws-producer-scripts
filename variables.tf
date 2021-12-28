
variable "aws_region" {
  default = "us-west-2"
  type    = string
}
variable "msk_secret_name" {
  type    = string
  default = ""
}
variable "msk_cluster_name" {
  type    = string
}
variable "msk_ebs_vol" {
  type    = number
  default = 100
}
variable "msk_instance_type" {
  type    = string
  default = "kafka.t3.small"
}
variable "msk_nodes_count" {
  type    = number
  default = 3
}
variable "tags" {
  type = map(string)
}

// if create new vpc is true
variable "cidr_block" {
  default = "10.10.104.0/22"
  type    = string
}
variable "azs" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d"]
  type    = list(string)
}
variable "private_subnets" {
  type    = list(string)
  validation {
    condition = (
      length(var.private_subnets) >= 2
    )
    error_message = "The private_subnets must be for each az."
  }
}
variable "public_subnets" {
  default = ["10.10.106.0/25", "10.10.106.128/25", "10.10.107.0/25", "10.10.107.128/25"]
  type    = list(string)
  validation {
    condition = (
      length(var.public_subnets) >= 2
    )
    error_message = "The public_subnets must be for each az when creating new vpc."
  }
}
variable "vpc_name" {
  type    = string
  default = "screwdriver-producer"
}
variable "vpc_id" {
  type        = string
  description = "VPC id where conusmer function will be created"
  default = null
}
variable "kms_key_alias_name" {
    type = string
    description = "The alias name of the kms key"
    default = ""
}
variable "deploy_env" {
    type = string
    description = "The env name for deploy"
}