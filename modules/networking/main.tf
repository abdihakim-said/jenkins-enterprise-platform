#---------------------------------------------#
# Jenkins Enterprise Platform - Enhanced Network Module
# Author: Abdihakim Said
# Epic 4, Story 5.1: AWS Network Architecture
# Assignment 3: Update Terraform network module to add VPC endpoint
#---------------------------------------------#

# VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-vpc"
    Purpose = "Jenkins Enterprise Platform"
    Epic = "Epic-4-Security"
    Story = "Story-5.1-Network-Architecture"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "jenkins_igw" {
  vpc_id = aws_vpc.jenkins_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-igw"
  })
}

# Public Subnets for ALB
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.jenkins_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-subnet-${count.index + 1}"
    Type = "Public"
    Tier = "Web"
  })
}

# Private Subnets for Jenkins instances
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-subnet-${count.index + 1}"
    Type = "Private"
    Tier = "Application"
  })
}

# Database Subnets for RDS (if needed)
resource "aws_subnet" "database_subnets" {
  count = length(var.database_subnet_cidrs)

  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-database-subnet-${count.index + 1}"
    Type = "Database"
    Tier = "Data"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_eips" {
  count = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0

  domain = "vpc"
  depends_on = [aws_internet_gateway.jenkins_igw]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "nat_gateways" {
  count = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0

  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.jenkins_igw]
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.jenkins_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.jenkins_igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-rt"
    Type = "Public"
  })
}

resource "aws_route_table" "private_rt" {
  count = var.enable_nat_gateway ? length(var.private_subnet_cidrs) : 1

  vpc_id = aws_vpc.jenkins_vpc.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat_gateways[count.index % length(aws_nat_gateway.nat_gateways)].id
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-rt-${count.index + 1}"
    Type = "Private"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public_rta" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count = length(aws_subnet.private_subnets)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt[var.enable_nat_gateway ? count.index % length(aws_route_table.private_rt) : 0].id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.environment}-alb-sg"
  vpc_id      = aws_vpc.jenkins_vpc.id
  description = "Security group for Application Load Balancer"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-alb-sg"
    Purpose = "ALB Security Group"
  })
}

resource "aws_security_group" "jenkins_sg" {
  name_prefix = "${var.environment}-jenkins-sg"
  vpc_id      = aws_vpc.jenkins_vpc.id
  description = "Security group for Jenkins instances"

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NFS for EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-sg"
    Purpose = "Jenkins Security Group"
  })
}

# Assignment 3: VPC Endpoints for enhanced security and performance
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.jenkins_vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-s3-endpoint"
    Purpose = "S3 VPC Endpoint"
    Assignment = "Assignment-3-VPC-Endpoints"
  })
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.jenkins_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-endpoint"
    Purpose = "EC2 VPC Endpoint"
    Assignment = "Assignment-3-VPC-Endpoints"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.jenkins_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ssm-endpoint"
    Purpose = "SSM VPC Endpoint"
    Assignment = "Assignment-3-VPC-Endpoints"
  })
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = aws_vpc.jenkins_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ssm-messages-endpoint"
    Purpose = "SSM Messages VPC Endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = aws_vpc.jenkins_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-messages-endpoint"
    Purpose = "EC2 Messages VPC Endpoint"
  })
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.jenkins_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-cloudwatch-logs-endpoint"
    Purpose = "CloudWatch Logs VPC Endpoint"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.environment}-vpc-endpoints-sg"
  vpc_id      = aws_vpc.jenkins_vpc.id
  description = "Security group for VPC endpoints"

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpc-endpoints-sg"
    Purpose = "VPC Endpoints Security Group"
  })
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

# Network ACLs for additional security
resource "aws_network_acl" "private_nacl" {
  vpc_id     = aws_vpc.jenkins_vpc.id
  subnet_ids = aws_subnet.private_subnets[*].id

  # Allow inbound HTTP from ALB subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 8080
    to_port    = 8080
  }

  # Allow inbound SSH
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }

  # Allow inbound NFS
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 2049
    to_port    = 2049
  }

  # Allow inbound ephemeral ports
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-nacl"
    Purpose = "Private Subnets Network ACL"
  })
}
