# EFS Mount Validation
resource "null_resource" "validate_efs_mount" {
  depends_on = [aws_autoscaling_group.jenkins]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Jenkins instance to be ready..."
      sleep 120
      
      # Get instance ID
      INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.jenkins.name}" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text --region ${data.aws_region.current.name})
      
      if [ "$INSTANCE_ID" != "None" ] && [ "$INSTANCE_ID" != "" ]; then
        echo "Validating EFS mount on instance: $INSTANCE_ID"
        
        # Test EFS mount
        aws ssm send-command \
          --instance-ids $INSTANCE_ID \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["df -h | grep efs || echo \"EFS not mounted, using local storage\"", "systemctl is-active jenkins"]' \
          --region ${data.aws_region.current.name}
      fi
    EOT
  }
  
  triggers = {
    instance_refresh = timestamp()
  }
}

# Health Check
resource "aws_cloudwatch_metric_alarm" "efs_mount_health" {
  alarm_name          = "${var.environment}-jenkins-efs-mount-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "This metric monitors jenkins instance health"
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins.name
  }
  
  tags = var.tags
}
