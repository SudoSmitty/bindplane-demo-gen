#!/usr/bin/env bash
# scripts/lib/common.sh — sourced by all scripts, never executed directly.
# Local prerequisite: the `bindplane` CLI must be installed on the operator's machine.
# Install: https://docs.bindplane.observiq.com/docs/install-cli
set -euo pipefail

# ── Color log helpers ──────────────────────────────────────────────────────────
_setup_colors() {
  if command -v tput &>/dev/null && tput setaf 1 &>/dev/null; then
    _CLR_BLUE="$(tput setaf 6)"   # cyan
    _CLR_YELLOW="$(tput setaf 3)"
    _CLR_RED="$(tput setaf 1)"
    _CLR_RESET="$(tput sgr0)"
  else
    _CLR_BLUE=""
    _CLR_YELLOW=""
    _CLR_RED=""
    _CLR_RESET=""
  fi
}
_setup_colors

info() {
  printf '%s[INFO]%s %s\n' "${_CLR_BLUE}" "${_CLR_RESET}" "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "${_CLR_YELLOW}" "${_CLR_RESET}" "$*" >&2
}

err() {
  printf '%s[ERR]%s %s\n' "${_CLR_RED}" "${_CLR_RESET}" "$*" >&2
}

# ── load_env ──────────────────────────────────────────────────────────────────
# Usage: load_env [--skip-secrets]
# Sources $REPO/.env and validates required vars. Pass --skip-secrets to skip
# secret validation (for list/validate commands that don't need credentials).
load_env() {
  local skip_secrets=false
  if [[ "${1:-}" == "--skip-secrets" ]]; then
    skip_secrets=true
  fi

  local env_file="$REPO/.env"
  if [[ ! -f "$env_file" ]]; then
    err ".env file not found at $env_file"
    err "Copy .env.example to .env and fill in your values."
    exit 1
  fi

  set -a
  # shellcheck source=/dev/null
  source "$env_file"
  set +a

  if [[ "$skip_secrets" == false ]]; then
    local missing=()
    # BP_OPAMP_ENDPOINT + BP_SECRET_KEY are needed for collector enrollment (on the VM).
    # BP_API_KEY is needed for pipeline apply/delete via the bindplane CLI (on the operator's machine).
    [[ -z "${BP_OPAMP_ENDPOINT:-}" ]] && missing+=("BP_OPAMP_ENDPOINT")
    [[ -z "${BP_SECRET_KEY:-}" ]]     && missing+=("BP_SECRET_KEY")

    if [[ ${#missing[@]} -gt 0 ]]; then
      err "Required secret(s) not set in $env_file: ${missing[*]}"
      exit 1
    fi
  fi

  # Default BP_REMOTE_URL if not set in .env
  BP_REMOTE_URL="${BP_REMOTE_URL:-https://app.bindplane.com}"
}

# ── require_yq ────────────────────────────────────────────────────────────────
require_yq() {
  if ! command -v yq &>/dev/null; then
    err "yq is required. Install: brew install yq  (macOS) or  snap install yq  (Linux)"
    exit 1
  fi
}

# ── require_bindplane_cli ─────────────────────────────────────────────────────
# Errors with an install hint if the bindplane CLI is not on PATH.
# The CLI is a LOCAL prerequisite on the operator's machine; it is NOT installed
# on the demo VM (apply targets BindPlane Cloud directly from the operator's machine).
require_bindplane_cli() {
  if ! command -v bindplane &>/dev/null; then
    err "The 'bindplane' CLI is required and was not found on PATH."
    err "Install from: https://docs.bindplane.observiq.com/docs/install-cli"
    err "  macOS:  brew tap observiq/bindplane && brew install bindplane"
    err "  Linux:  curl -fsS https://raw.githubusercontent.com/observIQ/bindplane-op/main/install.sh | bash"
    exit 1
  fi
}

# ── bp_cli ────────────────────────────────────────────────────────────────────
# Thin wrapper that runs the bindplane CLI against BP_REMOTE_URL with BP_API_KEY.
# Usage: bp_cli <subcommand> [args...]
# The API key is passed via --api-key flag and is never echoed to stdout/stderr.
# BP_REMOTE_URL defaults to https://app.bindplane.com (set in load_env).
bp_cli() {
  bindplane --remote-url "$BP_REMOTE_URL" --api-key "$BP_API_KEY" "$@"
}

# ── BindPlane CLI helpers ─────────────────────────────────────────────────────
# Use bp_cli (defined above) or require_bindplane_cli before invoking.
# The legacy curl-based bp_api / bp_api_with_code helpers have been removed;
# all BindPlane operations now go through the official CLI.

# ── manifest_get ──────────────────────────────────────────────────────────────
# Usage: manifest_get <demo> <yq-path>
# Example: manifest_get manufacturing .collectors.total
manifest_get() {
  local demo="$1"
  local yq_path="$2"
  require_yq
  yq eval "${yq_path}" "$REPO/demos/${demo}/manifest.yaml"
}

# ── resolve_cloud ─────────────────────────────────────────────────────────────
# Pick the active cloud: explicit CLOUD env var (azure|aws), else default 'azure'.
# Echoes the resolved value AND exports CLOUD so subsequent calls are no-ops.
# Validates against the set of terraform/<cloud>/ root modules that actually exist.
resolve_cloud() {
  local raw
  raw="$(printf '%s' "${CLOUD:-azure}" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    azure|aws) ;;
    *)
      err "Unknown CLOUD '$raw'. Supported: azure, aws."
      exit 1
      ;;
  esac
  if [[ ! -d "$REPO/terraform/$raw" ]]; then
    err "terraform/$raw/ root not found in repo."
    exit 1
  fi
  export CLOUD="$raw"
  printf '%s' "$raw"
}

# ── tf ────────────────────────────────────────────────────────────────────────
# Thin wrapper around terraform that targets the active cloud's root module.
# Usage: tf init  /  tf apply -auto-approve
# Reads $CLOUD (default 'azure'); validate via resolve_cloud first if you need
# to fail-fast with a clean error.
tf() {
  local cloud="${CLOUD:-azure}"
  terraform -chdir="$REPO/terraform/$cloud" "$@"
}

# ── require_aws_cli ───────────────────────────────────────────────────────────
# Errors with an install hint if the aws CLI is not on PATH, OR if no AWS
# credentials can be resolved by the standard provider chain (env vars, profile,
# IAM role). The actual credential check uses `aws sts get-caller-identity`
# which is the canonical "am I authenticated?" probe — it never echoes secrets.
require_aws_cli() {
  if ! command -v aws &>/dev/null; then
    err "The 'aws' CLI is required for CLOUD=aws and was not found on PATH."
    err "Install:  brew install awscli   (macOS)"
    err "          https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
  fi
  # Honour AWS_PROFILE if set; the AWS CLI picks it up automatically.
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    err "AWS credentials not resolved by the CLI credential chain."
    err "Try one of:"
    err "  • aws configure                 (interactive — writes ~/.aws/credentials)"
    err "  • aws sso login --profile <name> (then set AWS_PROFILE=<name> in .env)"
    err "  • export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in your shell"
    exit 1
  fi
}

# ── demo_exists ───────────────────────────────────────────────────────────────
# Returns 0 if demos/<name>/manifest.yaml exists, 1 otherwise.
demo_exists() {
  local name="$1"
  [[ -f "$REPO/demos/${name}/manifest.yaml" ]]
}

# ── resolve_owner_tag ─────────────────────────────────────────────────────────
# Produce a stable per-operator identifier for Azure resource naming + tagging.
# Source order:
#   1. $OWNER_TAG already in env (from .env or shell export)
#   2. `whoami`, sanitised
# The result is always lowercased, stripped to [a-z0-9], and truncated to 12 chars.
# If sanitisation leaves an empty string, falls back to "operator".
# Echoes the resolved value AND exports it as OWNER_TAG so subsequent calls are no-ops.
resolve_owner_tag() {
  local raw="${OWNER_TAG:-}"
  if [[ -z "$raw" ]]; then
    raw="$(whoami 2>/dev/null || echo operator)"
  fi
  # Lowercase, keep only a-z0-9, trim to 12 chars.
  local sanitized
  sanitized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-12)"
  [[ -z "$sanitized" ]] && sanitized="operator"
  export OWNER_TAG="$sanitized"
  printf '%s' "$sanitized"
}

# ── repo_root / REPO ──────────────────────────────────────────────────────────
# Walk up from scripts/lib/ until we find a directory containing CLAUDE.md.
_resolve_repo_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Walk up from scripts/lib/ to find repo root (has CLAUDE.md)
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/CLAUDE.md" ]] && { echo "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  echo "ERROR: could not find repo root (CLAUDE.md not found)" >&2
  exit 1
}
REPO="${REPO:-$(_resolve_repo_root)}"
