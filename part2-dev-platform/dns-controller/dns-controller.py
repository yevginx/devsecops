#!/usr/bin/env python3
"""
DNS Controller for Development Platform
Automatically manages DNS records for SSH/SFTP access to development environments
"""

import asyncio
import logging
import os
import json
from typing import Dict, List, Optional
from datetime import datetime, timedelta

import boto3
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DNSController:
    """
    DNS Controller for managing Route53 records for development environments
    """
    
    def __init__(self):
        # Load Kubernetes config
        try:
            config.load_incluster_config()
        except:
            config.load_kube_config()
        
        self.k8s_core = client.CoreV1Api()
        self.k8s_apps = client.AppsV1Api()
        
        # AWS clients
        self.route53 = boto3.client('route53')
        self.ec2 = boto3.client('ec2')
        
        # Configuration
        self.hosted_zone_id = os.getenv('HOSTED_ZONE_ID')
        self.domain_suffix = os.getenv('DOMAIN_SUFFIX', 'dev-platform.company.com')
        self.ssh_port = int(os.getenv('SSH_PORT', '22'))
        self.sftp_port = int(os.getenv('SFTP_PORT', '22'))
        
        # Internal state
        self.managed_records: Dict[str, Dict] = {}
        
        if not self.hosted_zone_id:
            raise ValueError("HOSTED_ZONE_ID environment variable is required")
    
    async def start(self):
        """Start the DNS controller"""
        logger.info("Starting DNS Controller")
        
        # Initial sync
        await self.sync_existing_records()
        
        # Watch for service changes
        await asyncio.gather(
            self.watch_services(),
            self.cleanup_stale_records()
        )
    
    async def sync_existing_records(self):
        """Sync existing DNS records with current services"""
        logger.info("Syncing existing DNS records")
        
        try:
            # Get all services with dev-env label
            services = self.k8s_core.list_service_for_all_namespaces(
                label_selector="app.kubernetes.io/managed-by=dev-platform"
            )
            
            for service in services.items:
                await self.process_service_event('ADDED', service)
                
        except ApiException as e:
            logger.error(f"Failed to sync existing records: {e}")
    
    async def watch_services(self):
        """Watch for Kubernetes service events"""
        logger.info("Starting service watcher")
        
        w = watch.Watch()
        
        while True:
            try:
                for event in w.stream(
                    self.k8s_core.list_service_for_all_namespaces,
                    label_selector="app.kubernetes.io/managed-by=dev-platform",
                    timeout_seconds=300
                ):
                    event_type = event['type']
                    service = event['object']
                    
                    await self.process_service_event(event_type, service)
                    
            except Exception as e:
                logger.error(f"Service watcher error: {e}")
                await asyncio.sleep(10)
    
    async def process_service_event(self, event_type: str, service):
        """Process a Kubernetes service event"""
        service_name = service.metadata.name
        namespace = service.metadata.namespace
        
        logger.info(f"Processing {event_type} event for service {namespace}/{service_name}")
        
        if event_type in ['ADDED', 'MODIFIED']:
            await self.create_or_update_dns_record(service)
        elif event_type == 'DELETED':
            await self.delete_dns_record(service)
    
    async def create_or_update_dns_record(self, service):
        """Create or update DNS record for a service"""
        try:
            service_name = service.metadata.name
            namespace = service.metadata.namespace
            
            # Extract environment ID from labels
            env_id = service.metadata.labels.get('environment-id')
            if not env_id:
                logger.warning(f"Service {namespace}/{service_name} missing environment-id label")
                return
            
            # Get LoadBalancer ingress
            ingress = self.get_service_ingress(service)
            if not ingress:
                logger.info(f"Service {namespace}/{service_name} has no external ingress yet")
                return
            
            # Create DNS record
            hostname = f"{env_id[:8]}.{self.domain_suffix}"
            
            await self.create_route53_record(
                hostname=hostname,
                target=ingress,
                record_type='CNAME' if ingress.endswith('.elb.amazonaws.com') else 'A',
                env_id=env_id,
                service_name=f"{namespace}/{service_name}"
            )
            
            # Store in managed records
            self.managed_records[env_id] = {
                'hostname': hostname,
                'target': ingress,
                'service': f"{namespace}/{service_name}",
                'created_at': datetime.utcnow().isoformat(),
                'last_updated': datetime.utcnow().isoformat()
            }
            
            logger.info(f"DNS record created/updated: {hostname} -> {ingress}")
            
        except Exception as e:
            logger.error(f"Failed to create DNS record: {e}")
    
    async def delete_dns_record(self, service):
        """Delete DNS record for a service"""
        try:
            # Extract environment ID from labels
            env_id = service.metadata.labels.get('environment-id')
            if not env_id or env_id not in self.managed_records:
                return
            
            record_info = self.managed_records[env_id]
            hostname = record_info['hostname']
            target = record_info['target']
            
            await self.delete_route53_record(
                hostname=hostname,
                target=target,
                record_type='CNAME' if target.endswith('.elb.amazonaws.com') else 'A'
            )
            
            # Remove from managed records
            del self.managed_records[env_id]
            
            logger.info(f"DNS record deleted: {hostname}")
            
        except Exception as e:
            logger.error(f"Failed to delete DNS record: {e}")
    
    def get_service_ingress(self, service) -> Optional[str]:
        """Get the external ingress point for a service"""
        if service.status and service.status.load_balancer:
            if service.status.load_balancer.ingress:
                ingress = service.status.load_balancer.ingress[0]
                return ingress.hostname or ingress.ip
        return None
    
    async def create_route53_record(self, hostname: str, target: str, record_type: str, 
                                  env_id: str, service_name: str):
        """Create Route53 DNS record"""
        try:
            change_batch = {
                'Comment': f'DNS record for dev environment {env_id}',
                'Changes': [
                    {
                        'Action': 'UPSERT',
                        'ResourceRecordSet': {
                            'Name': hostname,
                            'Type': record_type,
                            'TTL': 300,
                            'ResourceRecords': [{'Value': target}]
                        }
                    }
                ]
            }
            
            response = self.route53.change_resource_record_sets(
                HostedZoneId=self.hosted_zone_id,
                ChangeBatch=change_batch
            )
            
            logger.info(f"Route53 change submitted: {response['ChangeInfo']['Id']}")
            
        except Exception as e:
            logger.error(f"Failed to create Route53 record: {e}")
            raise
    
    async def delete_route53_record(self, hostname: str, target: str, record_type: str):
        """Delete Route53 DNS record"""
        try:
            change_batch = {
                'Comment': f'Delete DNS record for {hostname}',
                'Changes': [
                    {
                        'Action': 'DELETE',
                        'ResourceRecordSet': {
                            'Name': hostname,
                            'Type': record_type,
                            'TTL': 300,
                            'ResourceRecords': [{'Value': target}]
                        }
                    }
                ]
            }
            
            response = self.route53.change_resource_record_sets(
                HostedZoneId=self.hosted_zone_id,
                ChangeBatch=change_batch
            )
            
            logger.info(f"Route53 deletion submitted: {response['ChangeInfo']['Id']}")
            
        except Exception as e:
            logger.error(f"Failed to delete Route53 record: {e}")
            raise
    
    async def cleanup_stale_records(self):
        """Periodically cleanup stale DNS records"""
        while True:
            try:
                await asyncio.sleep(3600)  # Run every hour
                
                logger.info("Running stale record cleanup")
                
                # Get all managed records older than 24 hours with no corresponding service
                cutoff_time = datetime.utcnow() - timedelta(hours=24)
                
                stale_records = []
                for env_id, record_info in self.managed_records.items():
                    created_at = datetime.fromisoformat(record_info['created_at'])
                    
                    if created_at < cutoff_time:
                        # Check if service still exists
                        service_name = record_info['service']
                        namespace, name = service_name.split('/', 1)
                        
                        try:
                            self.k8s_core.read_namespaced_service(name=name, namespace=namespace)
                        except ApiException as e:
                            if e.status == 404:
                                stale_records.append(env_id)
                
                # Clean up stale records
                for env_id in stale_records:
                    record_info = self.managed_records[env_id]
                    await self.delete_route53_record(
                        hostname=record_info['hostname'],
                        target=record_info['target'],
                        record_type='CNAME' if record_info['target'].endswith('.elb.amazonaws.com') else 'A'
                    )
                    del self.managed_records[env_id]
                    logger.info(f"Cleaned up stale record for environment {env_id}")
                
            except Exception as e:
                logger.error(f"Cleanup task error: {e}")

class SFTPController:
    """
    SFTP Controller for managing SFTP access to development environments
    Based on AWS Transfer Family pattern from Loma Linda implementation
    """
    
    def __init__(self):
        self.transfer_client = boto3.client('transfer')
        self.iam_client = boto3.client('iam')
        self.s3_client = boto3.client('s3')
        
        # Configuration
        self.transfer_server_id = os.getenv('TRANSFER_SERVER_ID')
        self.s3_bucket = os.getenv('SFTP_S3_BUCKET')
        self.base_role_arn = os.getenv('SFTP_BASE_ROLE_ARN')
        
        if not all([self.transfer_server_id, self.s3_bucket, self.base_role_arn]):
            logger.warning("SFTP controller not fully configured")
    
    async def create_sftp_user(self, env_id: str, username: str, public_key: str) -> Dict:
        """Create SFTP user for development environment"""
        try:
            # Create user-specific IAM role
            role_name = f"sftp-{env_id[:8]}-{username}"
            
            # Create S3 path for user
            s3_path = f"/{self.s3_bucket}/environments/{env_id}"
            
            # Create Transfer Family user
            response = self.transfer_client.create_user(
                ServerId=self.transfer_server_id,
                UserName=f"{env_id[:8]}-{username}",
                Role=self.base_role_arn,
                HomeDirectory=s3_path,
                HomeDirectoryType='LOGICAL',
                HomeDirectoryMappings=[
                    {
                        'Entry': '/',
                        'Target': s3_path
                    }
                ],
                SshPublicKeyBody=public_key,
                Tags=[
                    {
                        'Key': 'Environment',
                        'Value': env_id
                    },
                    {
                        'Key': 'ManagedBy',
                        'Value': 'dev-platform'
                    }
                ]
            )
            
            logger.info(f"SFTP user created: {env_id[:8]}-{username}")
            
            return {
                'username': f"{env_id[:8]}-{username}",
                'sftp_endpoint': f"{self.transfer_server_id}.server.transfer.{boto3.Session().region_name}.amazonaws.com",
                's3_path': s3_path
            }
            
        except Exception as e:
            logger.error(f"Failed to create SFTP user: {e}")
            raise
    
    async def delete_sftp_user(self, env_id: str, username: str):
        """Delete SFTP user for development environment"""
        try:
            user_name = f"{env_id[:8]}-{username}"
            
            self.transfer_client.delete_user(
                ServerId=self.transfer_server_id,
                UserName=user_name
            )
            
            logger.info(f"SFTP user deleted: {user_name}")
            
        except Exception as e:
            logger.error(f"Failed to delete SFTP user: {e}")

async def main():
    """Main entry point"""
    logger.info("Starting DNS and SFTP Controllers")
    
    dns_controller = DNSController()
    
    try:
        await dns_controller.start()
    except KeyboardInterrupt:
        logger.info("Shutting down controllers")
    except Exception as e:
        logger.error(f"Controller error: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(main())
