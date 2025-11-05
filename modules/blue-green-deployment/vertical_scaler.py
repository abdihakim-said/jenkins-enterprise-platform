#!/usr/bin/env python3
"""
Automatic Vertical Scaling for Jenkins Master
Monitors CPU/Memory and scales instance type up/down
"""

import json
import os
import boto3
from datetime import datetime, timedelta

autoscaling = boto3.client('autoscaling')
ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

BLUE_ASG_NAME = os.environ['BLUE_ASG_NAME']
GREEN_ASG_NAME = os.environ['GREEN_ASG_NAME']
INSTANCE_TYPES = json.loads(os.environ['INSTANCE_TYPES'])
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

# Thresholds
CPU_SCALE_UP_THRESHOLD = 75
CPU_SCALE_DOWN_THRESHOLD = 30
MEMORY_SCALE_UP_THRESHOLD = 80
MEMORY_SCALE_DOWN_THRESHOLD = 40

def lambda_handler(event, context):
    """Main handler for vertical scaling"""
    
    print(f"Starting vertical scaling check at {datetime.now()}")
    
    # Get active ASG (the one with instances)
    active_asg = get_active_asg()
    if not active_asg:
        print("No active ASG found")
        return {'status': 'no_active_asg'}
    
    print(f"Active ASG: {active_asg['AutoScalingGroupName']}")
    
    # Get current instance type
    current_instance_type = get_current_instance_type(active_asg)
    if not current_instance_type:
        print("Could not determine current instance type")
        return {'status': 'no_instance_type'}
    
    print(f"Current instance type: {current_instance_type}")
    
    # Get metrics
    cpu_avg = get_cpu_utilization(active_asg)
    memory_avg = get_memory_utilization(active_asg)
    
    print(f"CPU: {cpu_avg}%, Memory: {memory_avg}%")
    
    # Determine if scaling is needed
    new_instance_type = determine_scaling_action(
        current_instance_type, 
        cpu_avg, 
        memory_avg
    )
    
    if new_instance_type == current_instance_type:
        print("No scaling needed")
        return {
            'status': 'no_action',
            'current_type': current_instance_type,
            'cpu': cpu_avg,
            'memory': memory_avg
        }
    
    # Perform vertical scaling
    print(f"Scaling from {current_instance_type} to {new_instance_type}")
    result = perform_vertical_scaling(
        active_asg,
        current_instance_type,
        new_instance_type
    )
    
    # Send notification
    send_notification(
        current_instance_type,
        new_instance_type,
        cpu_avg,
        memory_avg,
        result['status']
    )
    
    return result

def get_active_asg():
    """Get the ASG that currently has instances"""
    for asg_name in [BLUE_ASG_NAME, GREEN_ASG_NAME]:
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        
        if response['AutoScalingGroups']:
            asg = response['AutoScalingGroups'][0]
            if asg['DesiredCapacity'] > 0:
                return asg
    
    return None

def get_current_instance_type(asg):
    """Get instance type from launch template"""
    lt_id = asg['LaunchTemplate']['LaunchTemplateId']
    lt_version = asg['LaunchTemplate']['Version']
    
    response = ec2.describe_launch_template_versions(
        LaunchTemplateId=lt_id,
        Versions=[lt_version]
    )
    
    if response['LaunchTemplateVersions']:
        return response['LaunchTemplateVersions'][0]['LaunchTemplateData']['InstanceType']
    
    return None

def get_cpu_utilization(asg):
    """Get average CPU utilization for last 10 minutes"""
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{
                'Name': 'AutoScalingGroupName',
                'Value': asg['AutoScalingGroupName']
            }],
            StartTime=datetime.utcnow() - timedelta(minutes=10),
            EndTime=datetime.utcnow(),
            Period=600,
            Statistics=['Average']
        )
        
        if response['Datapoints']:
            return round(response['Datapoints'][0]['Average'], 2)
    except Exception as e:
        print(f"Error getting CPU metrics: {e}")
    
    return 0

def get_memory_utilization(asg):
    """Get average memory utilization for last 10 minutes"""
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='CWAgent',
            MetricName='MemoryUtilization',
            Dimensions=[{
                'Name': 'AutoScalingGroupName',
                'Value': asg['AutoScalingGroupName']
            }],
            StartTime=datetime.utcnow() - timedelta(minutes=10),
            EndTime=datetime.utcnow(),
            Period=600,
            Statistics=['Average']
        )
        
        if response['Datapoints']:
            return round(response['Datapoints'][0]['Average'], 2)
    except Exception as e:
        print(f"Error getting memory metrics: {e}")
    
    return 0

def determine_scaling_action(current_type, cpu, memory):
    """Determine if scaling up or down is needed"""
    
    current_index = INSTANCE_TYPES.index(current_type)
    
    # Scale UP if CPU or Memory high
    if cpu > CPU_SCALE_UP_THRESHOLD or memory > MEMORY_SCALE_UP_THRESHOLD:
        if current_index < len(INSTANCE_TYPES) - 1:
            return INSTANCE_TYPES[current_index + 1]
    
    # Scale DOWN if both CPU and Memory low
    if cpu < CPU_SCALE_DOWN_THRESHOLD and memory < MEMORY_SCALE_DOWN_THRESHOLD:
        if current_index > 0:
            return INSTANCE_TYPES[current_index - 1]
    
    return current_type

def perform_vertical_scaling(asg, old_type, new_type):
    """Perform vertical scaling by updating launch template"""
    
    try:
        # Get current launch template
        lt_id = asg['LaunchTemplate']['LaunchTemplateId']
        
        response = ec2.describe_launch_template_versions(
            LaunchTemplateId=lt_id,
            Versions=['$Latest']
        )
        
        current_lt = response['LaunchTemplateVersions'][0]['LaunchTemplateData']
        
        # Create new version with new instance type
        new_version = ec2.create_launch_template_version(
            LaunchTemplateId=lt_id,
            SourceVersion='$Latest',
            LaunchTemplateData={
                'InstanceType': new_type
            }
        )
        
        print(f"Created launch template version: {new_version['LaunchTemplateVersion']['VersionNumber']}")
        
        # Update ASG to use new version
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=asg['AutoScalingGroupName'],
            LaunchTemplate={
                'LaunchTemplateId': lt_id,
                'Version': '$Latest'
            }
        )
        
        # Trigger instance refresh for gradual rollout
        autoscaling.start_instance_refresh(
            AutoScalingGroupName=asg['AutoScalingGroupName'],
            Strategy='Rolling',
            Preferences={
                'MinHealthyPercentage': 100,
                'InstanceWarmup': 300
            }
        )
        
        print(f"Started instance refresh for {asg['AutoScalingGroupName']}")
        
        return {
            'status': 'success',
            'old_type': old_type,
            'new_type': new_type,
            'asg': asg['AutoScalingGroupName']
        }
        
    except Exception as e:
        print(f"Error performing vertical scaling: {e}")
        return {
            'status': 'error',
            'error': str(e)
        }

def send_notification(old_type, new_type, cpu, memory, status):
    """Send SNS notification about scaling action"""
    
    subject = f"Jenkins Vertical Scaling: {old_type} → {new_type}"
    
    message = f"""
Jenkins Master Vertical Scaling

Status: {status}
Old Instance Type: {old_type}
New Instance Type: {new_type}

Metrics:
- CPU Utilization: {cpu}%
- Memory Utilization: {memory}%

Timestamp: {datetime.now().isoformat()}

The instance will be replaced with the new type during the next refresh cycle.
"""
    
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        print("Notification sent")
    except Exception as e:
        print(f"Error sending notification: {e}")
