jupyter_hub_auth_mechanism = "demo"

region = "us-west-2"

# Optional SNS topic to receive Prometheus/Alertmanager notifications for idle pods, OOM events, etc.
notification_sns_topic_arn = "arn:aws:sns:us-west-2:123456789012:jupyterhub-alerts"

domain_name = "mlopswish.com"

# AWS Transfer Family (SFTP) configuration
# Legacy Transfer server (key-based) disabled; using password-based module now
enable_transfer_server = false
transfer_allowed_cidrs = []
transfer_users         = {}
