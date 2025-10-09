output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

output "grafana_admin_secret_name" {
  description = "AWS Secrets Manager secret name that stores the Grafana admin password"
  value       = aws_secretsmanager_secret.grafana.name
}

output "transfer_server_endpoint" {
  description = "Hostname of the AWS Transfer Family SFTP endpoint (empty when disabled)"
  value       = try(aws_transfer_server.sftp[0].endpoint, "")
}

output "transfer_server_dns" {
  description = "Managed Route53 record for the SFTP endpoint"
  value       = var.transfer_hostname
}

output "vpc_id" {
  description = "VPC ID for use by nested modules like VPN"
  value       = module.vpc.vpc_id
}

output "private_subnet_id" {
  description = "First private subnet ID for VPN endpoint"
  value       = module.vpc.private_subnets[0]
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}
