import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
autoscaling = boto3.client('autoscaling')
elbv2 = boto3.client('elbv2')
sns = boto3.client('sns')
cloudwatch = boto3.client('logs')

def handler(event, context):
    """
    Enterprise Blue/Green Deployment Orchestrator
    Handles automated deployment switching and health validation
    """
    
    try:
        # Get environment variables
        blue_asg_name = os.environ['BLUE_ASG_NAME']
        green_asg_name = os.environ['GREEN_ASG_NAME']
        target_group_arn = os.environ['TARGET_GROUP_ARN']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        log_group_name = os.environ['LOG_GROUP_NAME']
        
        logger.info(f"Starting deployment orchestration at {datetime.now()}")
        
        # Determine current active deployment
        active_deployment = get_active_deployment(blue_asg_name, green_asg_name, target_group_arn)
        logger.info(f"Current active deployment: {active_deployment}")
        
        # Check if deployment switch is requested
        if event.get('action') == 'switch':
            return handle_deployment_switch(
                blue_asg_name, green_asg_name, target_group_arn, 
                sns_topic_arn, active_deployment
            )
        
        # Perform health checks on active deployment
        health_status = perform_health_checks(active_deployment, blue_asg_name, green_asg_name)
        
        # Log health status
        log_deployment_status(log_group_name, active_deployment, health_status)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Health check completed',
                'active_deployment': active_deployment,
                'health_status': health_status,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in deployment orchestrator: {str(e)}")
        send_alert(sns_topic_arn, f"Deployment orchestrator error: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def get_active_deployment(blue_asg_name, green_asg_name, target_group_arn):
    """Determine which deployment is currently active"""
    
    try:
        # Get target group targets
        response = elbv2.describe_target_health(TargetGroupArn=target_group_arn)
        
        if not response['TargetHealthDescriptions']:
            return None
        
        # Get instance IDs from target group
        target_instance_ids = [target['Target']['Id'] for target in response['TargetHealthDescriptions']]
        
        # Check blue ASG instances
        blue_response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[blue_asg_name]
        )
        blue_instances = [instance['InstanceId'] for instance in blue_response['AutoScalingGroups'][0]['Instances']]
        
        # Check if any blue instances are in target group
        if any(instance_id in target_instance_ids for instance_id in blue_instances):
            return 'blue'
        else:
            return 'green'
            
    except Exception as e:
        logger.error(f"Error determining active deployment: {str(e)}")
        return None

def handle_deployment_switch(blue_asg_name, green_asg_name, target_group_arn, sns_topic_arn, current_active):
    """Handle blue/green deployment switch"""
    
    try:
        if current_active == 'blue':
            # Switch from blue to green
            new_active = 'green'
            new_asg_name = green_asg_name
            old_asg_name = blue_asg_name
        else:
            # Switch from green to blue
            new_active = 'blue'
            new_asg_name = blue_asg_name
            old_asg_name = green_asg_name
        
        logger.info(f"Switching from {current_active} to {new_active}")
        
        # Step 1: Scale up new environment
        logger.info(f"Scaling up {new_active} environment")
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=new_asg_name,
            MinSize=1,
            MaxSize=3,
            DesiredCapacity=1
        )
        
        # Step 2: Wait for new instances to be healthy
        wait_for_healthy_instances(new_asg_name, target_group_arn)
        
        # Step 3: Perform health checks on new environment
        if not validate_new_deployment_health(new_asg_name):
            # Rollback if health checks fail
            logger.error(f"Health checks failed for {new_active}, rolling back")
            rollback_deployment(old_asg_name, new_asg_name, target_group_arn, sns_topic_arn)
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Deployment failed health checks, rolled back'})
            }
        
        # Step 4: Switch traffic to new environment
        switch_traffic(new_asg_name, target_group_arn)
        
        # Step 5: Scale down old environment
        logger.info(f"Scaling down {current_active} environment")
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=old_asg_name,
            MinSize=0,
            MaxSize=0,
            DesiredCapacity=0
        )
        
        # Send success notification
        send_alert(sns_topic_arn, f"Deployment switch completed: {current_active} -> {new_active}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully switched from {current_active} to {new_active}',
                'new_active': new_active,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error during deployment switch: {str(e)}")
        send_alert(sns_topic_arn, f"Deployment switch failed: {str(e)}")
        raise

def perform_health_checks(active_deployment, blue_asg_name, green_asg_name):
    """Perform comprehensive health checks on active deployment"""
    
    if not active_deployment:
        return {'status': 'unknown', 'message': 'No active deployment found'}
    
    try:
        asg_name = blue_asg_name if active_deployment == 'blue' else green_asg_name
        
        # Get ASG instances
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        
        instances = response['AutoScalingGroups'][0]['Instances']
        
        if not instances:
            return {'status': 'unhealthy', 'message': 'No instances in ASG'}
        
        healthy_instances = [i for i in instances if i['HealthStatus'] == 'Healthy']
        
        health_percentage = len(healthy_instances) / len(instances) * 100
        
        return {
            'status': 'healthy' if health_percentage >= 100 else 'degraded',
            'healthy_instances': len(healthy_instances),
            'total_instances': len(instances),
            'health_percentage': health_percentage
        }
        
    except Exception as e:
        logger.error(f"Error performing health checks: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def wait_for_healthy_instances(asg_name, target_group_arn, timeout=600):
    """Wait for instances to become healthy"""
    import time
    
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            # Check ASG instance health
            response = autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[asg_name]
            )
            
            instances = response['AutoScalingGroups'][0]['Instances']
            healthy_instances = [i for i in instances if i['HealthStatus'] == 'Healthy']
            
            if len(healthy_instances) >= 1:
                logger.info(f"Instances in {asg_name} are healthy")
                return True
                
            time.sleep(30)
            
        except Exception as e:
            logger.error(f"Error waiting for healthy instances: {str(e)}")
            time.sleep(30)
    
    raise Exception(f"Timeout waiting for healthy instances in {asg_name}")

def validate_new_deployment_health(asg_name):
    """Validate health of new deployment before switching traffic"""
    # Implementation would include application-specific health checks
    # For now, return True if instances are running
    
    try:
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        
        instances = response['AutoScalingGroups'][0]['Instances']
        healthy_instances = [i for i in instances if i['HealthStatus'] == 'Healthy']
        
        return len(healthy_instances) >= 1
        
    except Exception as e:
        logger.error(f"Error validating deployment health: {str(e)}")
        return False

def switch_traffic(new_asg_name, target_group_arn):
    """Switch traffic to new deployment"""
    # This would typically involve updating the target group
    # For this implementation, we assume the ASG handles target registration
    logger.info(f"Traffic switched to {new_asg_name}")

def rollback_deployment(old_asg_name, new_asg_name, target_group_arn, sns_topic_arn):
    """Rollback deployment in case of failure"""
    
    try:
        logger.info("Rolling back deployment")
        
        # Scale up old environment
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=old_asg_name,
            MinSize=1,
            MaxSize=3,
            DesiredCapacity=1
        )
        
        # Scale down new environment
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=new_asg_name,
            MinSize=0,
            MaxSize=0,
            DesiredCapacity=0
        )
        
        send_alert(sns_topic_arn, "Deployment rolled back due to health check failures")
        
    except Exception as e:
        logger.error(f"Error during rollback: {str(e)}")
        send_alert(sns_topic_arn, f"Rollback failed: {str(e)}")

def log_deployment_status(log_group_name, active_deployment, health_status):
    """Log deployment status to CloudWatch"""
    
    try:
        log_stream_name = f"deployment-orchestrator-{datetime.now().strftime('%Y-%m-%d')}"
        
        log_event = {
            'timestamp': int(datetime.now().timestamp() * 1000),
            'message': json.dumps({
                'active_deployment': active_deployment,
                'health_status': health_status,
                'timestamp': datetime.now().isoformat()
            })
        }
        
        cloudwatch.put_log_events(
            logGroupName=log_group_name,
            logStreamName=log_stream_name,
            logEvents=[log_event]
        )
        
    except Exception as e:
        logger.error(f"Error logging deployment status: {str(e)}")

def send_alert(sns_topic_arn, message):
    """Send alert notification"""
    
    try:
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject="Jenkins Blue/Green Deployment Alert"
        )
    except Exception as e:
        logger.error(f"Error sending alert: {str(e)}")
