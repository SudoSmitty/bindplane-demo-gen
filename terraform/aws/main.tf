# ── Network (VPC, subnet, IGW, route table, security group) ──────────────────
module "network" {
  source = "./modules/network"

  name_suffix       = local.name_suffix
  admin_source_cidr = var.admin_source_cidr
  tags              = local.common_tags
}

# ── EC2 instance + EIP + key pair ────────────────────────────────────────────
module "ec2" {
  source = "./modules/ec2"

  name_suffix       = local.name_suffix
  instance_type     = local.effective_instance_type
  admin_username    = var.admin_username
  ssh_public_key    = var.ssh_public_key
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.security_group_id
  # Render cloud-init template and base64-encode inline. Uses the shared template
  # at terraform/cloud-init.tftpl — identical bootstrap for Azure and AWS.
  user_data = base64encode(templatefile("${path.module}/../cloud-init.tftpl", {
    demo              = var.demo
    bp_opamp_endpoint = var.bp_opamp_endpoint
    bp_secret_key     = var.bp_secret_key
    admin_username    = var.admin_username
  }))
  tags = local.common_tags
}
