# Password‑based SFTP for AWS Transfer Family (EFS)

This Terraform module provisions an AWS Transfer Family SFTP server that authenticates with a Lambda function using a PBKDF2 password digest. Successful logins land in an Amazon EFS path (default: `/shared`).

## What it creates
- AWS Transfer Family SFTP server (PUBLIC, EFS domain)
- Lambda for password auth (PBKDF2 SHA256, 1M iterations)
- IAM roles and policies for EFS client access and logging

## Inputs
- `region` (string): AWS region
- `efs_id` (string): EFS filesystem ID (e.g., `fs-0123456789abcdef0`)
- `efs_shared_subpath` (string): EFS subpath presented to users (default `/shared`)
- `sftp_username` (string): Login username (default `data-scientist`)
- `sftp_password_length` (number): Random password length (default `20`)

## Outputs
- `sftp_endpoint`: Transfer endpoint hostname
- `sftp_username`: Username configured
- `sftp_password` (sensitive): Generated password

## Deploy
```bash
terraform init
terraform apply
terraform output -raw sftp_endpoint
terraform output -raw sftp_password
```

## Connect
```bash
sftp <username>@<endpoint>
# example:
sftp data-scientist@s-xxxxxxxxxxxx.server.transfer.<region>.amazonaws.com
```
Optionally create a CNAME (e.g., `sftp.example.com`) to the endpoint.

## Notes
- The plaintext password is a Terraform output and is stored in state; only the PBKDF2 digest is provided to Lambda.
- Rotate by tainting the password resource and re‑applying:
  ```bash
  terraform taint random_password.sftp_password && terraform apply
  ```
- Restrict access with security controls at the network/DNS layer as needed.