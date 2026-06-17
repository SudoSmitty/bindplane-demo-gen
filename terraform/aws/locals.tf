locals {
  # Read the selected demo's manifest — the single source of truth for per-demo settings.
  manifest = yamldecode(file("${path.module}/../../demos/${var.demo}/manifest.yaml"))

  # Human-readable display name from the manifest.
  display_name = local.manifest.display_name

  # Total collector count; used in tags for visibility.
  collector_total = local.manifest.collectors.total

  # Allow the manifest to carry an optional vm_size_hint; fall back to the Terraform variable.
  # The same hint can carry an Azure SKU (Standard_*) or an EC2 type (t3.*, m6i.*, etc.) —
  # only use it on AWS if it does NOT start with "Standard_" (the Azure SKU prefix).
  raw_hint           = try(local.manifest.vm_size_hint, "")
  manifest_hint_is_ec2 = local.raw_hint != "" && !startswith(local.raw_hint, "Standard_")
  effective_instance_type = local.manifest_hint_is_ec2 ? local.raw_hint : var.instance_type

  # Stable name suffix derived from the demo slug + per-operator owner tag, so multiple
  # operators can deploy demos side-by-side in the same AWS account without colliding
  # on VPC / instance / key-pair names. Example: bpdemo-clintons-energy.
  name_suffix = "${var.resource_prefix}-${var.owner}-${var.demo}"

  # Common tags applied to every resource (via provider default_tags).
  common_tags = {
    demo            = var.demo
    display_name    = local.display_name
    owner           = var.owner
    managed_by      = "terraform"
    collector_total = tostring(local.collector_total)
    Name            = local.name_suffix
  }
}
