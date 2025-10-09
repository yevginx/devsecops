variable "region" {
  description = "AWS region"
  type        = string
}

variable "efs_id" {
  description = "EFS filesystem ID (e.g., fs-0123456789abcdef0)"
  type        = string
}

variable "efs_shared_subpath" {
  description = "EFS subpath to expose as SFTP home (default: /shared)"
  type        = string
  default     = "/shared"
}

variable "sftp_username" {
  description = "SFTP username for password authentication"
  type        = string
  default     = "data-scientist"
}

variable "sftp_password_length" {
  description = "Length of the generated SFTP password"
  type        = number
  default     = 20
  
  validation {
    condition     = var.sftp_password_length >= 12 && var.sftp_password_length <= 50
    error_message = "Password length must be between 12 and 50 characters."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
