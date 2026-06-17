#!/usr/bin/env bash
# scripts/down.sh — tear down the running demo on Azure or AWS.
# Usage: scripts/down.sh [--demo <name>] [--cloud azure|aws] [--purge-bindplane]
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Tear down the running demo environment on Azure or AWS.

Options:
  --demo <name>        Demo name to destroy (inferred from Terraform state if omitted)
  --cloud <name>       Target cloud: azure (default) or aws.
                       Can also be set via CLOUD=<name> in .env or shell env.
                       MUST match the cloud used at up.sh time — each cloud keeps
                       its own terraform state under terraform/<cloud>/.
  --purge-bindplane    Also delete BindPlane Agents, Fleets, Configurations, and Destinations
                       for this demo (in dependency order). Default: OFF — these resources
                       persist server-side and are re-applied on next up.sh. Use this only if
                       you want a fully clean BindPlane project.
  -h, --help           Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --demo manufacturing
  $(basename "$0") --demo manufacturing --cloud aws
  $(basename "$0") --demo manufacturing --purge-bindplane
EOF
}

# ── parse args ────────────────────────────────────────────────────────────────
DEMO=""
PURGE_BINDPLANE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo)
      [[ -n "${2:-}" ]] || { err "--demo requires a value"; exit 1; }
      DEMO="$2"
      shift 2
      ;;
    --cloud)
      [[ -n "${2:-}" ]] || { err "--cloud requires a value"; exit 1; }
      export CLOUD="$2"
      shift 2
      ;;
    --purge-bindplane)
      PURGE_BINDPLANE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

# ── load env ──────────────────────────────────────────────────────────────────
load_env

# ── resolve cloud (after load_env so .env can set CLOUD) ─────────────────────
CLOUD="$(resolve_cloud)"
info "Target cloud: $CLOUD"

if [[ "$CLOUD" == "aws" ]]; then
  require_aws_cli
fi

# ── determine demo name ───────────────────────────────────────────────────────
if [[ -z "$DEMO" ]]; then
  # Try reading from terraform state outputs
  DEMO="$(tf output -raw demo 2>/dev/null || true)"
fi

if [[ -z "$DEMO" ]]; then
  # Fall back: inspect tf show JSON for a demo output value
  DEMO="$(tf show -json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('values',{}).get('outputs',{}).get('demo',{}).get('value',''))" \
    2>/dev/null || true)"
fi

if [[ -z "$DEMO" ]]; then
  err "Could not determine which demo is deployed."
  err "Pass --demo <name> explicitly, e.g.:  scripts/down.sh --demo manufacturing"
  err "Available demos:"
  bash "$REPO/scripts/demos.sh" list 2>/dev/null || true
  exit 1
fi

info "Tearing down demo: $DEMO"

# ── export TF_VARs ────────────────────────────────────────────────────────────
export TF_VAR_demo="${DEMO}"
export TF_VAR_bp_opamp_endpoint="$BP_OPAMP_ENDPOINT"
export TF_VAR_bp_secret_key="$BP_SECRET_KEY"

# Per-cloud TF_VARs. Must match the values used by up.sh or terraform will plan
# replacements/recreates that defeat the destroy.
if [[ "$CLOUD" == "azure" ]]; then
  export TF_VAR_location="${AZURE_LOCATION:-eastus}"
  export TF_VAR_vm_size="${VM_SIZE:-Standard_B2s}"
  : "${ADMIN_USERNAME:=azureuser}"
  export TF_VAR_admin_username="$ADMIN_USERNAME"
else
  export TF_VAR_region="${AWS_REGION:-us-east-1}"
  export TF_VAR_instance_type="${EC2_INSTANCE_TYPE:-t3.small}"
  export TF_VAR_aws_profile="${AWS_PROFILE:-}"
  : "${ADMIN_USERNAME:=ubuntu}"
  export TF_VAR_admin_username="$ADMIN_USERNAME"
  [[ -n "${AWS_PROFILE:-}" ]] && export AWS_PROFILE
fi

# Owner tag — MUST match the value used at up.sh time or terraform will plan a
# replacement of a different (non-existent) resource group. resolve_owner_tag
# uses the same source order as up.sh ($OWNER_TAG → whoami).
export TF_VAR_owner="$(resolve_owner_tag)"

# ssh_public_key needed for destroy plan too
SSH_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
if [[ -f "$SSH_KEY_PATH" ]]; then
  export TF_VAR_ssh_public_key="$(cat "$SSH_KEY_PATH")"
else
  export TF_VAR_ssh_public_key="placeholder"  # destroy doesn't need the real key
fi

export TF_VAR_admin_source_cidr="${ADMIN_SOURCE_CIDR:-0.0.0.0/0}"

# ── best-effort collector drain ───────────────────────────────────────────────
info "Draining collectors (best-effort, freeing BindPlane cap)..."
PUBLIC_IP="$(tf output -raw public_ip 2>/dev/null || true)"
DEFAULT_USER="$([[ "$CLOUD" == "aws" ]] && echo ubuntu || echo azureuser)"
ADMIN_USER="$(tf output -raw admin_username 2>/dev/null || echo "$DEFAULT_USER")"

if [[ -n "$PUBLIC_IP" ]]; then
  SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"
  if ssh $SSH_OPTS "$ADMIN_USER@$PUBLIC_IP" \
       "cd /opt/demo/$DEMO && sudo docker compose down" 2>/dev/null; then
    info "Collectors drained successfully."
  else
    warn "Could not SSH to drain collectors — proceeding with destroy anyway."
    warn "BindPlane may show stale agents briefly; they will disappear once enrollment TTL expires."
  fi
else
  warn "Could not determine VM IP — skipping collector drain."
fi

# ── optional: purge BindPlane resources ──────────────────────────────────────
# Run BEFORE terraform destroy so BP_API_KEY is still in env and demo dir exists.
if [[ "$PURGE_BINDPLANE" == "true" ]]; then
  info "Purging BindPlane resources for demo '$DEMO' (--purge-bindplane set)..."
  bash "$REPO/scripts/bp-delete.sh" --demo "$DEMO" || {
    warn "bp-delete.sh encountered errors — continuing with terraform destroy."
    warn "You may need to manually clean up BindPlane resources in the UI."
  }
else
  info "Skipping BindPlane resource cleanup (use --purge-bindplane to remove them)."
fi

# ── terraform destroy ─────────────────────────────────────────────────────────
info "Destroying infrastructure for demo '$DEMO'..."
tf destroy -auto-approve -var "demo=$DEMO"

# ── confirm and remind ────────────────────────────────────────────────────────
if [[ "$CLOUD" == "azure" ]]; then
  info "Resource group destroyed. Azure resources are gone."
else
  info "EC2 instance, VPC, EIP and key pair destroyed. AWS resources are gone."
fi
info ""
if [[ "$PURGE_BINDPLANE" == "true" ]]; then
  info "BindPlane Agents, Fleets, Configurations, and Destinations for demo '$DEMO' were also deleted."
else
  info "NOTE: BindPlane Agents, Fleets, Configurations, and Destinations for demo '$DEMO'"
  info "      persist server-side (intended). Disconnected agents and configs will be"
  info "      re-used on next 'scripts/up.sh --demo $DEMO'."
  info "      To remove them now: scripts/bp-delete.sh --demo $DEMO"
  info "      Or: scripts/down.sh --demo $DEMO --purge-bindplane"
fi
