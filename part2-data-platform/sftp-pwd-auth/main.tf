provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  efs_arn = "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${var.efs_id}"
}

# IAM role for SFTP user
resource "aws_iam_role" "sftp_user" {
  name = "sftp-user-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy document for SFTP user to mount/write EFS via Transfer
data "aws_iam_policy_document" "sftp_user_policy" {
  statement {
    sid     = "EfsClientAccess"
    effect  = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]
    resources = [local.efs_arn]
  }

  statement {
    sid     = "EfsDescribe"
    effect  = "Allow"
    actions = [
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets"
    ]
    resources = ["*"]
  }
}

# IAM policy for SFTP user
resource "aws_iam_policy" "sftp_user_policy" {
  name   = "sftp-user-policy"
  policy = data.aws_iam_policy_document.sftp_user_policy.json
  tags   = var.tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "sftp_user_policy" {
  role       = aws_iam_role.sftp_user.name
  policy_arn = aws_iam_policy.sftp_user_policy.arn
}

# Generate secure password with automation-friendly special characters
resource "random_password" "sftp_password" {
  length           = var.sftp_password_length
  special          = true
  override_special = "!#$%*+-=?@"  # safe for shells and JSON
}

# Generate password digest for Lambda
data "external" "sftp_password_digest" {
  program = ["python3", "-c", <<-EOT
import hashlib
import json
import sys

password = "${random_password.sftp_password.result}"
salt = b'uMaVww64FUnDLcWF'
iterations = 1000000

dk = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations)
digest = dk.hex()

print(json.dumps({"digest": digest}))
EOT
  ]
}

# IAM role for Transfer Family logging
resource "aws_iam_role" "transfer_logging" {
  name = "sftp-transfer-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for Transfer Family logging
resource "aws_iam_role_policy_attachment" "transfer_logging" {
  role       = aws_iam_role.transfer_logging.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransferLoggingAccess"
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name = "sftp-auth-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for SFTP authentication
resource "aws_lambda_function" "sftp_auth" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "sftp-auth-${random_pet.lambda_suffix.id}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "auth_lambda.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = 30

  environment {
    variables = {
      TRANSFER_PASSWORD        = data.external.sftp_password_digest.result.digest
      TRANSFER_ROLE            = aws_iam_role.sftp_user.arn
      TRANSFER_USERNAME        = var.sftp_username
      TRANSFER_HOME_DIRECTORY  = "/${var.efs_id}${var.efs_shared_subpath}"
      TRANSFER_UID             = "1000"
      TRANSFER_GID             = "100"
    }
  }
  tags = var.tags
}

# Random pet name for Lambda function uniqueness
resource "random_pet" "lambda_suffix" {
  length = 4
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/auth_lambda.py"
  output_path = "${path.module}/lambda/auth_lambda.zip"
}

# Lambda permission for Transfer Family
resource "aws_lambda_permission" "allow_transfer" {
  statement_id  = "AllowExecutionFromTransfer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sftp_auth.function_name
  principal     = "transfer.amazonaws.com"
}

# SFTP server
resource "aws_transfer_server" "sftp" {
  identity_provider_type       = "AWS_LAMBDA"
  function                     = aws_lambda_function.sftp_auth.arn
  protocols                    = ["SFTP"]
  domain                       = "EFS"
  endpoint_type                = "PUBLIC"
  sftp_authentication_methods  = "PASSWORD"
  logging_role                 = aws_iam_role.transfer_logging.arn
  tags                         = var.tags
}
