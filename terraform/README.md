# terraform/

Demo-agnostic root modules — one per cloud. Each provisions ONE ephemeral Ubuntu 22.04 VM per
demo run, using the shared `cloud-init.tftpl` bootstrap (Docker + `/opt/demo/.env`).

```
terraform/
  cloud-init.tftpl   # SHARED — same bootstrap for Azure and AWS
  azure/             # azurerm root: 1 resource group + VNet/subnet/NSG/PIP/NIC + Linux VM
  aws/               # aws root:     VPC/subnet/IGW/RT/SG + EC2 instance + EIP + key pair
```

Both roots expose the same outputs (`public_ip`, `admin_username`, `vm_name`, `demo`) so the
scripts in `scripts/` are cloud-symmetric: `scripts/up.sh --cloud azure|aws` is the only switch.

## Usage

`scripts/up.sh --demo <name> [--cloud azure|aws]` drives this entirely — it sources `.env`,
exports the right per-cloud `TF_VAR_*` set, runs `terraform apply -var demo=<name>` against the
selected root, waits for cloud-init, then `rsync`s the demo directory and starts `docker compose`.
Run `scripts/down.sh [--cloud ...]` to drain collectors and run `terraform destroy`.

Manual apply:

```bash
terraform -chdir=terraform/azure apply -var demo=manufacturing
terraform -chdir=terraform/aws   apply -var demo=manufacturing
```

## Credentials

- **Azure**: `az login` first; the `azurerm` provider uses the Azure CLI session.
- **AWS**: standard AWS CLI credential chain — env vars, `~/.aws/credentials` (`aws configure`),
  `~/.aws/config` (`aws sso login --profile <name>`), or EC2/ECS/SSO IAM role. **Never** put
  AWS access keys in `.env` or `.tfvars`. Set `AWS_PROFILE` in `.env` if you use a named profile.

## State

Each cloud root keeps its own state under `terraform/<cloud>/terraform.tfstate` (gitignored).
If you want to switch a running demo between clouds, run `scripts/down.sh` for the current cloud
first — you cannot move state across providers.
