output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.jenkins_vpc.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.jenkins_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private_subnets[*].id
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = aws_subnet.database_subnets[*].id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.jenkins_igw.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = aws_nat_gateway.nat_gateways[*].id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb_sg.id
}

output "jenkins_security_group_id" {
  description = "Jenkins security group ID"
  value       = aws_security_group.jenkins_sg.id
}

output "vpc_endpoints" {
  description = "VPC endpoint information"
  value = {
    s3                = aws_vpc_endpoint.s3.id
    ec2               = aws_vpc_endpoint.ec2.id
    ssm               = aws_vpc_endpoint.ssm.id
    ssm_messages      = aws_vpc_endpoint.ssm_messages.id
    ec2_messages      = aws_vpc_endpoint.ec2_messages.id
    cloudwatch_logs   = aws_vpc_endpoint.cloudwatch_logs.id
  }
}
