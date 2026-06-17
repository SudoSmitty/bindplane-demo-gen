output "instance_name" {
  description = "Name tag of the EC2 instance."
  value       = aws_instance.this.tags["Name"]
}

output "instance_id" {
  description = "Resource ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "public_ip_address" {
  description = "Auto-assigned public IPv4 of the instance (changes on stop/start)."
  value       = aws_instance.this.public_ip
}

output "admin_username" {
  description = "Admin username configured for SSH (matches the Ubuntu AMI default)."
  value       = var.admin_username
}
