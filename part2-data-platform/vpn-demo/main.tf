module "vpn_client" {
  source  = "babicamir/vpn-client/aws"
  version = "1.0.1"

  organization_name = "Swish Analytics"
  project-name      = "data-engineering-platform"
  environment       = "dev"

  # Network information
  vpc_id            = "vpc-0bc3119c1abb378c8"
  subnet_id         = "subnet-0c56cd9515cebed1f"
  client_cidr_block = "10.1.0.0/21"

  # VPN config options
  split_tunnel           = true
  vpn_inactive_period    = 3600 # 1 hour
  session_timeout_hours  = 24
  logs_retention_in_days = 365 # SOC2 requires retention of logs for 365 days

  # List of users for *.ovpn client configs (keep "root" user!)
  aws-vpn-client-list = ["root", "devsecops"]

}
