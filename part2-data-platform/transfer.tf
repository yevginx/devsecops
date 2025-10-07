locals {
  transfer_enabled = var.enable_transfer_server || length(var.transfer_users) > 0

  transfer_user_keys = local.transfer_enabled ? {
    for item in flatten([
      for user, cfg in var.transfer_users : [
        for idx, key in cfg.public_keys : {
          id   = "${user}-${idx}"
          user = user
          key  = key
        }
      ]
      ]) : item.id => {
      user = item.user
      key  = item.key
    }
  } : {}
}

resource "aws_security_group" "transfer" {
  count = local.transfer_enabled ? 1 : 0

  name        = "${local.name}-transfer"
  description = "Security group for AWS Transfer Family SFTP endpoint"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = var.transfer_allowed_cidrs
    content {
      description = "SFTP access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-transfer" })
}

resource "aws_cloudwatch_log_group" "transfer" {
  count = local.transfer_enabled ? 1 : 0

  name              = "/${local.name}/transfer"
  retention_in_days = 30
}

data "aws_iam_policy_document" "transfer_logging_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "transfer_logging" {
  count = local.transfer_enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [format("arn:aws:logs:%s:%s:log-group:%s:*", var.region, data.aws_caller_identity.current.account_id, aws_cloudwatch_log_group.transfer[0].name)]
  }
}

resource "aws_iam_role" "transfer_logging" {
  count = local.transfer_enabled ? 1 : 0

  name               = "${local.name}-transfer-logging"
  assume_role_policy = data.aws_iam_policy_document.transfer_logging_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "transfer_logging" {
  count = local.transfer_enabled ? 1 : 0

  name   = "${local.name}-transfer-logging"
  role   = aws_iam_role.transfer_logging[0].id
  policy = data.aws_iam_policy_document.transfer_logging[0].json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "transfer_access_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "transfer_access" {
  count = local.transfer_enabled ? 1 : 0

  statement {
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]
    resources = [aws_efs_file_system.efs.arn]
  }

  statement {
    actions = [
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "transfer_access" {
  count = local.transfer_enabled ? 1 : 0

  name               = "${local.name}-transfer-access"
  assume_role_policy = data.aws_iam_policy_document.transfer_access_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "transfer_access" {
  count = local.transfer_enabled ? 1 : 0

  name   = "${local.name}-transfer-access"
  role   = aws_iam_role.transfer_access[0].id
  policy = data.aws_iam_policy_document.transfer_access[0].json
}

resource "aws_transfer_server" "sftp" {
  count = local.transfer_enabled ? 1 : 0

  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "PUBLIC"
  domain                 = "EFS"
  protocols              = ["SFTP"]
  security_policy_name   = "TransferSecurityPolicy-2023-05"
  logging_role           = aws_iam_role.transfer_logging[0].arn

  tags = merge(local.tags, { Name = "${local.name}-transfer" })
}

resource "aws_transfer_user" "this" {
  for_each = local.transfer_enabled ? var.transfer_users : {}

  server_id = aws_transfer_server.sftp[0].id
  user_name = each.key
  role      = aws_iam_role.transfer_access[0].arn

  home_directory      = "/"
  home_directory_type = "LOGICAL"

  home_directory_mappings {
    entry = "/"
    target = format(
      "/%s/shared",
      aws_efs_file_system.efs.id
    )
  }

  posix_profile {
    uid = try(each.value.uid, 1000)
    gid = try(each.value.gid, 100)
  }

  depends_on = [aws_iam_role_policy.transfer_access]
}

resource "aws_transfer_ssh_key" "this" {
  for_each = local.transfer_user_keys

  server_id = aws_transfer_server.sftp[0].id
  user_name = each.value.user
  body      = each.value.key

  depends_on = [aws_transfer_user.this]
}

