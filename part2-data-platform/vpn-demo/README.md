# AWS Client VPN

## Overview

This terraform module creates all necessary AWS services, certificates, keys, and *.ovpn configuration files. With this module, you avoid the need to manually generate CA, server, client keys, and certificates - everything is automated.

- Certificates are stored in AWS ACM
- Keys are stored in AWS SSM Parameter Store
- Configuration files are stored in S3 bucket (`{project-name}-{environment}-vpn-config-files`)

## Connection Steps

1. **Install AWS VPN Client** on your laptop
   - Download from: https://aws.amazon.com/vpn/client-vpn-download/
   - macOS: `brew install --cask aws-vpn-client`

2. **Get VPN Profile**
   - After provisioning, download your .ovpn file from the S3 bucket

3. **Connect**
   - Open AWS VPN Client
   - Import the .ovpn file (File > Import)
   - Select the profile and connect