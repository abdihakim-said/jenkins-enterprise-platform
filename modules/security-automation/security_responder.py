import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Automated security incident response handler
    Processes GuardDuty findings and takes appropriate actions
    """
    
    # Initialize AWS clients
    sns = boto3.client('sns')
    ec2 = boto3.client('ec2')
    autoscaling = boto3.client('autoscaling')
    
    # Get environment variables
    environment = os.environ.get('ENVIRONMENT', 'dev')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    try:
        # Parse the GuardDuty finding
        detail = event.get('detail', {})
        finding_type = detail.get('type', 'Unknown')
        severity = detail.get('severity', 0)
        instance_id = None
        
        # Extract instance ID if available
        if 'resource' in detail and 'instanceDetails' in detail['resource']:
            instance_id = detail['resource']['instanceDetails'].get('instanceId')
        
        # Determine response based on finding type and severity
        response_actions = []
        
        if severity >= 8.0:  # High/Critical severity
            if 'Malware' in finding_type or 'Trojan' in finding_type:
                response_actions.append('ISOLATE_INSTANCE')
            elif 'Cryptocurrency' in finding_type:
                response_actions.append('TERMINATE_INSTANCE')
            elif 'Backdoor' in finding_type:
                response_actions.append('ISOLATE_INSTANCE')
        
        # Execute response actions
        for action in response_actions:
            if action == 'ISOLATE_INSTANCE' and instance_id:
                isolate_instance(ec2, instance_id)
            elif action == 'TERMINATE_INSTANCE' and instance_id:
                terminate_instance(ec2, autoscaling, instance_id, environment)
        
        # Send notification
        message = create_alert_message(detail, response_actions)
        if sns_topic_arn:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Security Alert - {finding_type}',
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Security response completed',
                'actions_taken': response_actions,
                'finding_type': finding_type,
                'severity': severity
            })
        }
        
    except Exception as e:
        print(f"Error processing security event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def isolate_instance(ec2, instance_id):
    """Isolate instance by modifying security groups"""
    try:
        # Create isolation security group
        response = ec2.create_security_group(
            GroupName=f'isolation-{instance_id}',
            Description='Isolation security group for compromised instance'
        )
        isolation_sg_id = response['GroupId']
        
        # Modify instance security groups
        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            Groups=[isolation_sg_id]
        )
        
        print(f"Instance {instance_id} isolated with security group {isolation_sg_id}")
        
    except Exception as e:
        print(f"Failed to isolate instance {instance_id}: {str(e)}")

def terminate_instance(ec2, autoscaling, instance_id, environment):
    """Terminate instance and trigger ASG replacement"""
    try:
        # Get ASG name from instance tags
        response = ec2.describe_instances(InstanceIds=[instance_id])
        tags = response['Reservations'][0]['Instances'][0].get('Tags', [])
        
        asg_name = None
        for tag in tags:
            if tag['Key'] == 'aws:autoscaling:groupName':
                asg_name = tag['Value']
                break
        
        # Terminate instance
        ec2.terminate_instances(InstanceIds=[instance_id])
        
        # If part of ASG, trigger replacement
        if asg_name:
            autoscaling.set_desired_capacity(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=1,
                HonorCooldown=False
            )
        
        print(f"Instance {instance_id} terminated, ASG {asg_name} will replace it")
        
    except Exception as e:
        print(f"Failed to terminate instance {instance_id}: {str(e)}")

def create_alert_message(detail, actions):
    """Create formatted alert message"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    message = f"""
SECURITY ALERT - Jenkins Enterprise Platform

Timestamp: {timestamp}
Finding Type: {detail.get('type', 'Unknown')}
Severity: {detail.get('severity', 'Unknown')}
Description: {detail.get('description', 'No description available')}

Resource Details:
- Instance ID: {detail.get('resource', {}).get('instanceDetails', {}).get('instanceId', 'N/A')}
- Region: {detail.get('region', 'N/A')}

Actions Taken:
{chr(10).join([f'- {action}' for action in actions]) if actions else '- No automated actions taken'}

Please review the Security Hub console for full details.
"""
    
    return message
