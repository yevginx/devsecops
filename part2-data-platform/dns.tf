# Creates a Route 53 public hosted zone for the domain
data "aws_route53_zone" "primary" {
  count = var.domain_name != "" ? 1 : 0

  name = var.domain_name
}

# Creates the CNAME record for the SFTP server (e.g., sftp.your-domain.com)
resource "aws_route53_record" "sftp" {
  count = var.domain_name != "" && local.transfer_enabled ? 1 : 0

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "sftp.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_transfer_server.sftp[0].endpoint]
}

data "kubernetes_service" "jupyterhub_proxy" {
  metadata {
    name      = "proxy-public"
    namespace = "jupyterhub"
  }

  depends_on = [module.eks_data_addons]
}

data "aws_lb" "jupyterhub_alb" {
  depends_on = [data.kubernetes_service.jupyterhub_proxy]

  tags = {
    "elbv2.k8s.aws/cluster"     = var.name
    "service.k8s.aws/resource"  = "LoadBalancer"
    "service.k8s.aws/stack"     = "jupyterhub/proxy-public"
  }
}

# Creates the A record for the JupyterHub UI (e.g., jupyter.your-domain.com)
resource "aws_route53_record" "jupyterhub" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "jupyter.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.jupyterhub_alb.dns_name
    zone_id                = data.aws_lb.jupyterhub_alb.zone_id
    evaluate_target_health = true
  }
}
