variable "name_suffix" {
  type        = string
  description = "Suffix appended to all EC2 resource names (e.g. bpdemo-jdoe-manufacturing)."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (e.g. t3.small)."
}

variable "admin_username" {
  type        = string
  description = "Linux admin username (Ubuntu AMI default: 'ubuntu')."
}

variable "ssh_public_key" {
  type        = string
  description = "Full openssh-format public key string for admin SSH access."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet to launch the instance into."
}

variable "security_group_id" {
  type        = string
  description = "Security group to attach to the instance ENI."
}

variable "user_data" {
  type        = string
  description = "Base64-encoded cloud-init payload."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the EC2 instance and EIP."
  default     = {}
}
