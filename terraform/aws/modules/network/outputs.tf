output "vpc_id" {
  description = "Resource ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Resource ID of the public subnet."
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Resource ID of the security group to attach to the instance."
  value       = aws_security_group.this.id
}
