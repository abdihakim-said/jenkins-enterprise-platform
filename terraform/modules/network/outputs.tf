# Network Module Outputs
# Jenkins Enterprise Platform - Network Module
# Version: 2.0

output "vpc_id" {
  description = "ID of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.existing[0].id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].arn : data.aws_vpc.existing[0].arn
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.create_vpc ? aws_internet_gateway.main[0].id : null
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = var.create_vpc ? aws_subnet.public[*].id : data.aws_subnets.existing_public[0].ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = var.create_vpc ? aws_subnet.private[*].id : data.aws_subnets.existing_private[0].ids
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = var.create_vpc ? aws_subnet.public[*].cidr_block : []
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = var.create_vpc ? aws_subnet.private[*].cidr_block : []
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = var.create_vpc ? aws_nat_gateway.main[*].id : []
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT Gateways"
  value       = var.create_vpc ? aws_eip.nat[*].public_ip : []
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = var.create_vpc ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = var.create_vpc ? aws_route_table.private[*].id : []
}

output "public_network_acl_id" {
  description = "ID of the public network ACL"
  value       = var.create_vpc ? aws_network_acl.public[0].id : null
}

output "private_network_acl_id" {
  description = "ID of the private network ACL"
  value       = var.create_vpc ? aws_network_acl.private[0].id : null
}

# Availability Zone information
output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}

output "public_subnets_by_az" {
  description = "Map of public subnets by availability zone"
  value = var.create_vpc ? {
    for idx, subnet in aws_subnet.public :
    subnet.availability_zone => subnet.id
  } : {}
}

output "private_subnets_by_az" {
  description = "Map of private subnets by availability zone"
  value = var.create_vpc ? {
    for idx, subnet in aws_subnet.private :
    subnet.availability_zone => subnet.id
  } : {}
}

# Network summary
output "network_summary" {
  description = "Summary of network configuration"
  value = {
    vpc_id                = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.existing[0].id
    vpc_cidr             = var.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block
    public_subnets_count = length(var.create_vpc ? aws_subnet.public : data.aws_subnets.existing_public[0].ids)
    private_subnets_count = length(var.create_vpc ? aws_subnet.private : data.aws_subnets.existing_private[0].ids)
    nat_gateways_count   = var.create_vpc ? length(aws_nat_gateway.main) : 0
    availability_zones   = var.availability_zones
  }
}
