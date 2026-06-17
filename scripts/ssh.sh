#!/usr/bin/env bash
# scripts/ssh.sh — SSH into the running demo VM.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

load_env --skip-secrets
CLOUD="$(resolve_cloud)"

# ── Read terraform outputs ──────────────────────────────────────────────────────────
PUBLIC_IP="$(tf output -raw public_ip 2>/dev/null || true)"
ADMIN_USER="$(tf output -raw admin_username 2>/dev/null || true)"

# Default admin username depends on cloud (Azure: azureuser, AWS Ubuntu: ubuntu)
DEFAULT_USER="$([[ "$CLOUD" == "aws" ]] && echo ubuntu || echo azureuser)"
ADMIN_USER="${ADMIN_USER:-$DEFAULT_USER}"

if [[ -z "$PUBLIC_IP" ]]; then
  err "No running VM found. Run scripts/up.sh first."
  exit 1
fi

info "Connecting to $ADMIN_USER@$PUBLIC_IP …"

exec ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$ADMIN_USER@$PUBLIC_IP" \
  "$@"
