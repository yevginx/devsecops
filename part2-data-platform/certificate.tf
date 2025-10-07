# --------------------------------------------------------------------------------
# Certificate Data Lookup & Self-Signed Fallback
# --------------------------------------------------------------------------------

data "aws_acm_certificate" "issued" {
  count = var.domain_name != "" ? 1 : 0

  domain   = "*.${var.domain_name}"
  statuses = ["ISSUED"]
}

resource "tls_private_key" "self_signed" {
  count = var.domain_name != "" && data.aws_acm_certificate.issued[0].arn == "" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count = var.domain_name != "" && data.aws_acm_certificate.issued[0].arn == "" ? 1 : 0

  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "jupyter.${var.domain_name}"
    organization = "Demo Env"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count = var.domain_name != "" && data.aws_acm_certificate.issued[0].arn == "" ? 1 : 0

  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  tags = merge(local.tags, {
    Name = "jupyter.${var.domain_name}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  certificate_arn = var.domain_name != "" ? (
    data.aws_acm_certificate.issued[0].arn != "" ? data.aws_acm_certificate.issued[0].arn : aws_acm_certificate.self_signed[0].arn
  ) : ""
}
