# Creates a Route 53 public hosted zone for the domain
data "aws_route53_zone" "primary" {
  count = var.domain_name != "" ? 1 : 0

  name = var.domain_name
}

# Creates the CNAME record for the SFTP server (e.g., sftp.your-domain.com)
resource "aws_route53_record" "sftp" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "sftp.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [module.sftp_pwd.sftp_endpoint]
}

data "kubernetes_service" "jupyterhub_proxy" {
  metadata {
    name      = "proxy-public"
    namespace = "jupyterhub"
  }

  depends_on = [module.eks_data_addons]
}

# Creates the A record for the JupyterHub UI (e.g., jupyter.your-domain.com)
resource "aws_route53_record" "jupyterhub" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.primary[0].zone_id
  name    = "jupyter.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [
    # Use the Kubernetes Service LoadBalancer hostname directly to avoid race conditions
    data.kubernetes_service.jupyterhub_proxy.status[0].load_balancer[0].ingress[0].hostname
  ]
  depends_on = [data.kubernetes_service.jupyterhub_proxy]
}
