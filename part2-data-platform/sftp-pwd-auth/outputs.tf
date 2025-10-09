output "sftp_endpoint" { 
  value = aws_transfer_server.sftp.endpoint
  description = "SFTP endpoint hostname" 
}

output "sftp_username" { 
  value = var.sftp_username
}

output "sftp_password" { 
  value = random_password.sftp_password.result 
  sensitive = true 
}
