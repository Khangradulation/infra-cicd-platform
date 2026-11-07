output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "AZs the subnets were placed in."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB and NAT gateways)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for ECS tasks)."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs (for additional gateway endpoints)."
  value       = aws_route_table.private[*].id
}

output "nat_gateway_count" {
  description = "Number of NAT gateways created (drives cost)."
  value       = local.nat_count
}

output "nat_public_ips" {
  description = "Elastic IPs used by NAT gateways (egress source IPs)."
  value       = aws_eip.nat[*].public_ip
}
