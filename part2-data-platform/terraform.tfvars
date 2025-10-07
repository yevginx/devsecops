jupyter_hub_auth_mechanism = "demo"

region = "us-west-2"

# Optional SNS topic to receive Prometheus/Alertmanager notifications for idle pods, OOM events, etc.
notification_sns_topic_arn = "arn:aws:sns:us-west-2:123456789012:jupyterhub-alerts"

domain_name = "mlopswish.com"

# AWS Transfer Family (SFTP) configuration
enable_transfer_server = true
transfer_allowed_cidrs = [
  "0.0.0.0/0"
]
transfer_users = {
  "data-scientist" = {
    public_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolIyJLaZHuZLnGSUEvZqckDZZw1Oa9+H/rSFKaqjJ0 evgenyglinskiy@gmail.com"
    ]
    uid  = 1000
    gid  = 100
    home = "data-scientist"
  }
}
