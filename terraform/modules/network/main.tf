# Network Module - Jenkins Enterprise Platform
# Creates VPC, subnets, gateways, and routing infrastructure
# Based on deployed infrastructure: vpc-0b221819e694d4c66
# Version: 2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources for existing VPC (if not creating new one)
data "aws_vpc" "existing" {
  count = var.create_vpc ? 0 : 1
  
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "existing_private" {
  count = var.create_vpc ? 0 : 1
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

data "aws_subnets" "existing_public" {
  count = var.create_vpc ? 0 : 1
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}

# VPC - Create new or use existing
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0
  
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-public-subnet-${count.index + 1}"
    Type = "public"
    Tier = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = var.create_vpc ? length(var.private_subnet_cidrs) : 0
  
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-private-subnet-${count.index + 1}"
    Type = "private"
    Tier = "private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0
  
  domain = "vpc"
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-nat-eip-${count.index + 1}"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-nat-gw-${count.index + 1}"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Route Tables - Public
resource "aws_route_table" "public" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-public-rt"
    Type = "public"
  })
}

# Route Tables - Private
resource "aws_route_table" "private" {
  count = var.create_vpc ? length(var.private_subnet_cidrs) : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-private-rt-${count.index + 1}"
    Type = "private"
  })
}

# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count = var.create_vpc ? length(var.public_subnet_cidrs) : 0
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Route Table Associations - Private
resource "aws_route_table_association" "private" {
  count = var.create_vpc ? length(var.private_subnet_cidrs) : 0
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Network ACLs - Public
resource "aws_network_acl" "public" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id     = aws_vpc.main[0].id
  subnet_ids = aws_subnet.public[*].id
  
  # Allow HTTP
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  
  # Allow HTTPS
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  # Allow SSH from VPC
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }
  
  # Allow ephemeral ports
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
    Name = "${var.environment}-${var.project_name}-public-nacl"
  })
}

# Network ACLs - Private
resource "aws_network_acl" "private" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id     = aws_vpc.main[0].id
  subnet_ids = aws_subnet.private[*].id
  
  # Allow traffic from VPC
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }
  
  # Allow ephemeral ports from internet (for outbound responses)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
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
    Name = "${var.environment}-${var.project_name}-private-nacl"
  })
}
