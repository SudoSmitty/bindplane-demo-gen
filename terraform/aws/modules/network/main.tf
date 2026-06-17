# ── Pick the first AZ in the region for the single-subnet demo ────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "vpc-${var.name_suffix}"
  })
}

# ── Public subnet (only subnet — single demo VM) ─────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # EIP attaches explicitly

  tags = merge(var.tags, {
    Name = "snet-${var.name_suffix}"
  })
}

# ── Internet Gateway + default route ─────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "igw-${var.name_suffix}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "rt-${var.name_suffix}"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security group (SSH in from admin CIDR, HTTPS out to anywhere) ───────────
# Note: AWS reserves the "sg-" prefix for security group IDs, so the `name`
# attribute cannot start with it. We use "<suffix>-sg" instead.
# Description is restricted to ASCII (no em-dash / unicode) per the EC2 API.
resource "aws_security_group" "this" {
  name        = "${var.name_suffix}-sg"
  description = "BindPlane demo VM - SSH in from admin CIDR, HTTPS out for OpAMP and Dynatrace OTLP"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_suffix}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.this.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_source_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS outbound (OpAMP wss + Dynatrace OTLP)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# DNS resolution (port 53) — egress only, both UDP and TCP.
resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS resolution (UDP)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS resolution (TCP)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}

# HTTP egress — needed for `apt-get update` from cloud-init (Ubuntu archive mirrors)
# and Docker repo bootstrap. Without this, cloud-init hangs and the demo never starts.
resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP outbound (apt mirrors, Docker repo bootstrap)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
