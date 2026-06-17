output "public_ip" {
  description = "Public IPv4 address of the demo EC2 instance (Elastic IP)."
  value       = module.ec2.public_ip_address
}

output "ssh_command" {
  description = "Ready-to-paste SSH command to reach the instance."
  value       = "ssh ${var.admin_username}@${module.ec2.public_ip_address}"
}

output "vm_name" {
  description = "Name tag of the EC2 instance."
  value       = module.ec2.instance_name
}

output "resource_group_name" {
  description = <<-EOT
    AWS has no resource-group concept; this echoes the demo's name_suffix as a stand-in
    so scripts that read this output work on both clouds.
  EOT
  value       = local.name_suffix
}

output "demo" {
  description = "The demo that was deployed."
  value       = var.demo
}

output "admin_username" {
  description = "Admin username on the demo instance (used by SSH)."
  value       = var.admin_username
}
