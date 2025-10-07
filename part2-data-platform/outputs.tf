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
