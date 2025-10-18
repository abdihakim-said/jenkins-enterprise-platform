import json
import boto3
import requests
import os
from datetime import datetime, timedelta
from decimal import Decimal

# AWS clients
autoscaling = boto3.client('autoscaling')
ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
s3 = boto3.client('s3')

# Configuration from environment
ENVIRONMENT = os.environ['ENVIRONMENT']
ASG_NAME = os.environ['ASG_NAME']
SNS_TOPIC = os.environ['SNS_TOPIC']
S3_BUCKET = os.environ['S3_BUCKET']
JENKINS_URL = os.environ.get('JENKINS_URL', 'http://localhost:8080')

def lambda_handler(event, context):
    """
    Jenkins Cost Optimization Lambda
    Runs every hour to optimize costs through intelligent scaling
    """
    try:
        print(f"🚀 Starting cost optimization for {ENVIRONMENT}")
        
        # Get current metrics
        jenkins_metrics = get_jenkins_metrics()
        infrastructure_costs = get_infrastructure_costs()
        scaling_decision = make_scaling_decision(jenkins_metrics)
        
        # Execute scaling if needed
        cost_impact = execute_scaling(scaling_decision)
        
        # Store optimization data
        optimization_data = {
            'timestamp': datetime.utcnow().isoformat(),
            'environment': ENVIRONMENT,
            'jenkins_metrics': jenkins_metrics,
            'infrastructure_costs': infrastructure_costs,
            'scaling_decision': scaling_decision,
            'cost_impact': cost_impact
        }
        
        store_optimization_data(optimization_data)
        
        # Send alerts if needed
        check_cost_alerts(infrastructure_costs)
        
        # Publish custom metrics
        publish_cost_metrics(infrastructure_costs, jenkins_metrics)
        
        print(f"✅ Cost optimization completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization completed',
                'cost_impact': cost_impact,
                'current_capacity': scaling_decision.get('current_capacity', 0)
            })
        }
        
    except Exception as e:
        print(f"❌ Error in cost optimization: {str(e)}")
        send_error_alert(str(e))
        raise

def get_jenkins_metrics():
    """Get Jenkins queue and executor metrics"""
    try:
        # In production, you'd use Jenkins API with authentication
        # For demo, we'll simulate realistic metrics
        
        current_hour = datetime.now().hour
        current_day = datetime.now().weekday()  # 0=Monday, 6=Sunday
        
        # Simulate realistic Jenkins usage patterns
        if current_day >= 5:  # Weekend
            queue_length = 0
            active_executors = 0
            idle_executors = 0
        elif current_hour < 8 or current_hour > 19:  # Off hours
            queue_length = 1 if current_hour in [7, 20] else 0
            active_executors = 0
            idle_executors = 0
        else:  # Business hours
            # Peak hours: 10-12, 14-16
            if current_hour in [10, 11, 14, 15]:
                queue_length = 5
                active_executors = 3
                idle_executors = 1
            else:
                queue_length = 2
                active_executors = 1
                idle_executors = 2
        
        return {
            'queue_length': queue_length,
            'active_executors': active_executors,
            'idle_executors': idle_executors,
            'total_executors': active_executors + idle_executors
        }
        
    except Exception as e:
        print(f"⚠️ Error getting Jenkins metrics: {str(e)}")
        return {
            'queue_length': 0,
            'active_executors': 0,
            'idle_executors': 0,
            'total_executors': 0
        }

def get_infrastructure_costs():
    """Get current infrastructure costs and capacity"""
    try:
        # Get current ASG capacity
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[ASG_NAME]
        )
        
        if not response['AutoScalingGroups']:
            current_capacity = 0
        else:
            current_capacity = response['AutoScalingGroups'][0]['DesiredCapacity']
        
        # Get current spot price
        spot_response = ec2.describe_spot_price_history(
            InstanceTypes=['t3.medium'],
            ProductDescriptions=['Linux/UNIX'],
            MaxResults=1
        )
        
        spot_price = float(spot_response['SpotPriceHistory'][0]['SpotPrice']) if spot_response['SpotPriceHistory'] else 0.012
        on_demand_price = 0.0416  # t3.medium on-demand price
        
        # Calculate costs
        hourly_cost = current_capacity * spot_price
        daily_cost = hourly_cost * 24
        monthly_cost = daily_cost * 30
        
        # Calculate savings vs on-demand
        on_demand_monthly = current_capacity * on_demand_price * 24 * 30
        monthly_savings = on_demand_monthly - monthly_cost
        savings_percent = (monthly_savings / on_demand_monthly * 100) if on_demand_monthly > 0 else 0
        
        return {
            'current_capacity': current_capacity,
            'spot_price': spot_price,
            'on_demand_price': on_demand_price,
            'hourly_cost': round(hourly_cost, 4),
            'daily_cost': round(daily_cost, 2),
            'monthly_cost': round(monthly_cost, 2),
            'monthly_savings': round(monthly_savings, 2),
            'savings_percent': round(savings_percent, 1)
        }
        
    except Exception as e:
        print(f"⚠️ Error getting infrastructure costs: {str(e)}")
        return {
            'current_capacity': 0,
            'spot_price': 0.012,
            'on_demand_price': 0.0416,
            'hourly_cost': 0,
            'daily_cost': 0,
            'monthly_cost': 0,
            'monthly_savings': 0,
            'savings_percent': 0
        }

def make_scaling_decision(jenkins_metrics):
    """Make intelligent scaling decision based on metrics"""
    queue_length = jenkins_metrics['queue_length']
    active_executors = jenkins_metrics['active_executors']
    idle_executors = jenkins_metrics['idle_executors']
    
    # Get current capacity
    response = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    )
    current_capacity = response['AutoScalingGroups'][0]['DesiredCapacity'] if response['AutoScalingGroups'] else 0
    
    # Scaling parameters
    MIN_WORKERS = 0
    MAX_WORKERS = 10
    SCALE_UP_THRESHOLD = 3
    
    target_capacity = current_capacity
    action = "no_change"
    reason = "Optimal capacity"
    
    # Check if it's off-hours
    current_hour = datetime.now().hour
    current_day = datetime.now().weekday()
    is_off_hours = (current_day >= 5) or (current_hour < 8 or current_hour > 19)
    
    # Scale up logic
    if queue_length > SCALE_UP_THRESHOLD:
        needed_workers = (queue_length + 1) // 2  # 2 jobs per worker
        target_capacity = min(current_capacity + needed_workers, MAX_WORKERS)
        action = "scale_up"
        reason = f"Queue backlog: {queue_length} jobs"
        
    # Scale down logic - off hours
    elif is_off_hours and queue_length == 0 and active_executors == 0:
        target_capacity = MIN_WORKERS
        action = "scale_down"
        reason = "Off-hours with no activity"
        
    # Scale down logic - excess idle workers
    elif queue_length == 0 and idle_executors > 2 and current_capacity > 1:
        target_capacity = max(current_capacity - 1, MIN_WORKERS)
        action = "scale_down"
        reason = f"Excess idle workers: {idle_executors}"
    
    return {
        'current_capacity': current_capacity,
        'target_capacity': target_capacity,
        'action': action,
        'reason': reason,
        'is_off_hours': is_off_hours
    }

def execute_scaling(scaling_decision):
    """Execute the scaling decision"""
    current_capacity = scaling_decision['current_capacity']
    target_capacity = scaling_decision['target_capacity']
    action = scaling_decision['action']
    reason = scaling_decision['reason']
    
    cost_impact = {
        'capacity_change': target_capacity - current_capacity,
        'hourly_change': 0,
        'daily_change': 0,
        'monthly_change': 0,
        'action_taken': False
    }
    
    if target_capacity != current_capacity:
        try:
            # Execute scaling
            autoscaling.set_desired_capacity(
                AutoScalingGroupName=ASG_NAME,
                DesiredCapacity=target_capacity,
                HonorCooldown=True
            )
            
            # Calculate cost impact
            spot_price = 0.012  # Average spot price
            capacity_change = target_capacity - current_capacity
            hourly_change = capacity_change * spot_price
            daily_change = hourly_change * 24
            monthly_change = daily_change * 30
            
            cost_impact.update({
                'hourly_change': round(hourly_change, 4),
                'daily_change': round(daily_change, 2),
                'monthly_change': round(monthly_change, 2),
                'action_taken': True
            })
            
            print(f"💰 SCALED: {current_capacity} → {target_capacity} workers ({reason})")
            print(f"💵 Cost impact: ${daily_change:.2f}/day, ${monthly_change:.2f}/month")
            
        except Exception as e:
            print(f"❌ Error executing scaling: {str(e)}")
            cost_impact['error'] = str(e)
    else:
        print(f"📊 No scaling needed: {current_capacity} workers optimal")
    
    return cost_impact

def store_optimization_data(data):
    """Store optimization data in S3 for analytics"""
    try:
        timestamp = datetime.utcnow()
        key = f"optimization-events/{timestamp.strftime('%Y/%m/%d')}/event-{timestamp.strftime('%H%M%S')}.json"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(data, indent=2),
            ContentType='application/json'
        )
        
        print(f"📊 Stored optimization data: s3://{S3_BUCKET}/{key}")
        
    except Exception as e:
        print(f"⚠️ Error storing optimization data: {str(e)}")

def check_cost_alerts(infrastructure_costs):
    """Check if cost alerts should be sent"""
    monthly_cost = infrastructure_costs['monthly_cost']
    budget_limit = 100  # $100/month budget
    
    usage_percent = (monthly_cost / budget_limit * 100) if budget_limit > 0 else 0
    
    if usage_percent > 80:
        alert_message = f"""
🚨 Jenkins Cost Alert - {ENVIRONMENT}

Current monthly cost: ${monthly_cost:.2f}
Budget limit: ${budget_limit:.2f}
Usage: {usage_percent:.1f}% of budget

Current capacity: {infrastructure_costs['current_capacity']} workers
Spot savings: {infrastructure_costs['savings_percent']:.1f}%

Action required: Review scaling policies or increase budget.
        """.strip()
        
        try:
            sns.publish(
                TopicArn=SNS_TOPIC,
                Message=alert_message,
                Subject=f"Jenkins Cost Alert - {ENVIRONMENT}"
            )
            print(f"🚨 Sent cost alert: {usage_percent:.1f}% of budget used")
            
        except Exception as e:
            print(f"⚠️ Error sending cost alert: {str(e)}")

def publish_cost_metrics(infrastructure_costs, jenkins_metrics):
    """Publish custom CloudWatch metrics"""
    try:
        metrics = [
            {
                'MetricName': 'MonthlyEstimatedCost',
                'Value': infrastructure_costs['monthly_cost'],
                'Unit': 'None'
            },
            {
                'MetricName': 'SpotSavingsPercent',
                'Value': infrastructure_costs['savings_percent'],
                'Unit': 'Percent'
            },
            {
                'MetricName': 'CurrentCapacity',
                'Value': infrastructure_costs['current_capacity'],
                'Unit': 'Count'
            },
            {
                'MetricName': 'JenkinsQueueLength',
                'Value': jenkins_metrics['queue_length'],
                'Unit': 'Count'
            }
        ]
        
        for metric in metrics:
            cloudwatch.put_metric_data(
                Namespace=f'Jenkins/CostOptimization/{ENVIRONMENT}',
                MetricData=[{
                    'MetricName': metric['MetricName'],
                    'Value': metric['Value'],
                    'Unit': metric['Unit'],
                    'Timestamp': datetime.utcnow()
                }]
            )
        
        print(f"📈 Published {len(metrics)} cost optimization metrics")
        
    except Exception as e:
        print(f"⚠️ Error publishing metrics: {str(e)}")

def send_error_alert(error_message):
    """Send error alert via SNS"""
    try:
        sns.publish(
            TopicArn=SNS_TOPIC,
            Message=f"Jenkins Cost Optimization Error in {ENVIRONMENT}:\n\n{error_message}",
            Subject=f"Jenkins Cost Optimization Error - {ENVIRONMENT}"
        )
    except Exception as e:
        print(f"⚠️ Error sending error alert: {str(e)}")
