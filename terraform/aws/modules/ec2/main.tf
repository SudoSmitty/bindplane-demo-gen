# ── Ubuntu 22.04 LTS AMI (Canonical) ─────────────────────────────────────────
# Looked up dynamically so we always get the latest patched image in the region.
# Canonical publishes both gp2- and gp3-backed AMIs under hvm-ssd/* — the
# instance overrides volume_type=gp3 on the root_block_device below.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ── Key pair (uploaded from operator's public key) ───────────────────────────
resource "aws_key_pair" "this" {
  key_name   = "key-${var.name_suffix}"
  public_key = var.ssh_public_key
  tags       = var.tags
}

# ── EC2 instance ─────────────────────────────────────────────────────────────
# Public IP is auto-assigned from the subnet (map_public_ip_on_launch=true) to
# avoid the regional EIP quota. The IP changes if the instance is stopped and
# started, which is acceptable for short-lived demo VMs (we don't stop them —
# `down.sh` tears the whole stack down).
resource "aws_instance" "this" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  user_data_base64            = var.user_data
  # IMDSv2 only (no insecure session-less metadata access)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    tags = merge(var.tags, {
      Name = "osdisk-${var.name_suffix}"
    })
  }

  tags = merge(var.tags, {
    Name = "vm-${var.name_suffix}"
  })
}
