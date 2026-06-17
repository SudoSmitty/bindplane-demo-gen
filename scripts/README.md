# scripts/ — Demo Operator Scripts

All scripts source `scripts/lib/common.sh`. Require: `yq` (brew install yq / snap install yq),
`terraform`, `ssh`, `rsync` (optional, falls back to scp), plus the CLI for your chosen cloud:

- **Azure** (default): `azure-cli` logged in (`az login`).
- **AWS** (opt-in via `--cloud aws` or `CLOUD=aws` in `.env`): `awscli` v2 with credentials
  resolved by the standard chain — env vars, `~/.aws/credentials` (`aws configure`),
  `~/.aws/config` (`aws sso login --profile <name>`), or IAM role. Credentials are NEVER
  stored in `.env` or `.tfvars`.

## Usage table

| Command | Description |
|---|---|
| `scripts/demos.sh list` | List all available demos with collector count |
| `scripts/up.sh [--demo NAME] [--cloud azure\|aws]` | Spin up a demo (prompts to pick if --demo omitted) |
| `scripts/up.sh --demo NAME --skip-validate` | Skip static validation (not recommended) |
| `scripts/down.sh [--demo NAME] [--cloud azure\|aws]` | Drain collectors + destroy cloud infra |
| `scripts/ssh.sh` | SSH into the running demo VM (cloud from `$CLOUD`) |
| `scripts/ssh.sh -L 8080:localhost:8080` | SSH with port-forward |
| `scripts/logs.sh --demo NAME` | Tail all docker compose logs from VM |
| `scripts/logs.sh --demo NAME gateway` | Tail logs for the gateway service only |
| `scripts/validate.sh NAME` | Static validation of a demo (8 checks) before spin-up |
| `scripts/select.sh` | Interactive picker (used internally by up.sh) |

## Quick start

```bash
cp .env.example .env
# fill in BP_SECRET_KEY, BP_API_KEY, DT_OTLP_ENDPOINT, DT_API_TOKEN in .env
# (optional) set CLOUD=aws to default to AWS, or pass --cloud aws per-run

scripts/up.sh                              # Azure (default), pick demo interactively
scripts/up.sh --demo manufacturing
scripts/up.sh --demo manufacturing --cloud aws
```

After spin-up, follow `demos/<name>/bindplane/rollout.md` for the optional live-rollout demo.
Then verify telemetry in Dynatrace.

## Tear down

```bash
scripts/down.sh --demo manufacturing                # uses $CLOUD or --cloud (must match up.sh)
scripts/down.sh --demo manufacturing --cloud aws
```

Drains collectors (frees BindPlane cap), then destroys the cloud infra atomically. BindPlane
server-side Configurations persist — on re-spin, collectors re-enroll and get their pipelines
pushed automatically.

## TF_VAR mapping

Shared (both clouds):

| Script variable (from .env) | Terraform variable |
|---|---|
| `BP_OPAMP_ENDPOINT` | `bp_opamp_endpoint` |
| `BP_SECRET_KEY` | `bp_secret_key` |
| `SSH_PUBLIC_KEY_PATH` (file content) | `ssh_public_key` |
| `ADMIN_SOURCE_CIDR` (auto-detected if blank) | `admin_source_cidr` |
| `OWNER_TAG` (or `whoami`) | `owner` |
| `--demo NAME` arg | `demo` |

Azure-only (when `CLOUD=azure`):

| Script variable (from .env) | Terraform variable |
|---|---|
| `AZURE_LOCATION` | `location` |
| `VM_SIZE` | `vm_size` |

AWS-only (when `CLOUD=aws`):

| Script variable (from .env) | Terraform variable |
|---|---|
| `AWS_REGION` | `region` |
| `EC2_INSTANCE_TYPE` | `instance_type` |
| `AWS_PROFILE` (optional) | `aws_profile` |

AWS credentials (access key / secret / session) come from the standard AWS CLI credential
chain — not from `.env` or `.tfvars`. Run `aws configure` or `aws sso login --profile <name>`
first.
