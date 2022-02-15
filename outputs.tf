output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc.id
}
# Subnets
output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = local.vpc.private_subnets
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.sd_msk_cluster.bootstrap_brokers_sasl_scram
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.sd_msk_cluster.zookeeper_connect_string
} 