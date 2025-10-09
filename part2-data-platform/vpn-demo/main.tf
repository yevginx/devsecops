data "terraform_remote_state" "platform" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

module "vpn_client" {
  source  = "babicamir/vpn-client/aws"
  version = "1.0.1"

  organization_name = "Swish Analytics"
  project-name      = "data-engineering-platform"
  environment       = "dev"

  # Network information - dynamically read from parent platform state
  vpc_id            = data.terraform_remote_state.platform.outputs.vpc_id
  subnet_id         = data.terraform_remote_state.platform.outputs.private_subnet_id
  client_cidr_block = "192.168.100.0/22" # VPN client IP pool (must not overlap with VPC CIDR)

  # VPN config options
  split_tunnel           = true
  vpn_inactive_period    = 3600 # 1 hour
  session_timeout_hours  = 24
  logs_retention_in_days = 365 # SOC2 requires retention of logs for 365 days

  # List of users for *.ovpn client configs (keep "root" user!)
  aws-vpn-client-list = ["root", "devsecops"]

}
