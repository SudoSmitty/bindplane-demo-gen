# bindplane-demo — Repo Conventions

Repeatable Dynatrace SE demos showing **BindPlane** (now a Dynatrace product) managing **fleets of
OpenTelemetry collectors** (BDOT — BindPlane Distro for OpenTelemetry). All three signals
(**logs + metrics + traces**) flow into Dynatrace. Two demos ship today (`manufacturing`,
`networking`); one runs at a time; more can be added with zero Terraform change.
The operator picks the cloud at spin-up: **Azure (default) or AWS** via `--cloud azure|aws`
(or `CLOUD=` in `.env`). The Terraform roots live under `terraform/azure/` and `terraform/aws/`
and share `terraform/cloud-init.tftpl`; the BindPlane / Docker / OpAMP layers above are identical
on both clouds.

## The Demo Contract (READ THIS BEFORE ADDING A DEMO)

Every `demos/<name>/` directory MUST contain:

| File / dir | Required | Purpose |
|---|---|---|
| `manifest.yaml` | ✅ | **Single source of truth.** Terraform + scripts read ONLY this; they never special-case a demo name. Defines collectors (≤10), labels, signal map, caps, BDOT image. |
| `docker-compose.yaml` | ✅ | BDOT collector containers + simulators + instrumented trace app. |
| `.env.demo` | ✅ | Non-secret knobs (intervals, device counts, intensity). |
| `collectors/*.env` | ✅ | Per-collector `OPAMP_LABELS` only. One file per collector in the manifest. |
| `simulators/` | ✅ | Containers that together emit **logs AND metrics AND traces**. |
| `bindplane/destinations.yaml` | ✅ | Apply-ready multi-doc YAML: Destination resources (`apiVersion/kind/metadata/spec`). Uses `${DT_ENV_ID}` + `${DT_API_TOKEN}` placeholders. Auto-applied by `up.sh`. |
| `bindplane/configurations.yaml` | ✅ | Apply-ready multi-doc YAML: Configuration resources with inline `spec.sources[]`, `spec.selector.matchLabels`, and `spec.destinations[]`. Auto-applied by `up.sh`. |
| `bindplane/fleets.yaml` | ✅ | Apply-ready YAML: TWO `kind: Fleet` resources per demo — one per role (`<demo>-gateway` + `<demo>-edge`). Each fleet pairs ONE Configuration with a role-keyed selector (`{demo: <name>, role: gateway\|edge}`). BindPlane's Fleet model requires a Configuration per Fleet; sharing `demo=<name>` in both selectors keeps the UI's demo filter intact. Auto-applied by `up.sh`. |
| `bindplane/rollout.md` | ✅ | Live Rollout demo runbook — optional UI step to add a processor and roll it out fleet-wide. |
| `README.md` | ✅ | One-paragraph what-it-shows + business variants. |

**Adding demo C** = `scripts/scaffold.sh c` (or the `demo-scaffold` skill) → fill in. No Terraform
edit. `scripts/demos.sh list` auto-discovers it via `demos/*/manifest.yaml`.

## Non-negotiable rules (a demo is INVALID if it breaks these)

1. **`collectors.total` ≤ 10** (BindPlane free-plan cap). One demo runs at a time.
2. **All three signals present** — `manifest.signals.{metrics,logs,traces}` each non-empty, each
   backed by a simulator/source in `docker-compose.yaml`.
3. **Dynatrace destination uses the managed `dynatrace_otlp` type** in `bindplane/destinations.yaml`
   with **`deployment_type: Custom`** + **`custom_url: "${DT_OTLP_ENDPOINT}"`** (the full
   `…/api/v2/otlp` URL) — works for ANY tenant (Gen3/sprint/labs, SaaS, managed) without guessing the
   host from an env id. `dynatrace_api_token` uses `${DT_API_TOKEN}`; never literal values.
   `telemetry_types` must include Metrics, Logs, and Traces. The managed destination handles delta
   temporality internally — no `cumulativetodelta` (and none is in the catalog). The DT token must
   carry all three ingest permissions — Gen 3 / OpenPipeline names: `openpipeline:metrics:ingest` +
   `openpipeline:logs:ingest` + `openpipeline:events:ingest` (Gen 2 classic: `metrics.ingest` +
   `logs.ingest` + `openTelemetryTrace.ingest`). A **403 on a signal = that ingest permission is
  missing** from the token (probe each: `POST $DT_OTLP_ENDPOINT/v1/{metrics,logs,traces}`).
4. **BDOT image is pinned** (`manifest.bdot_image`), never `:latest`.
5. **`caps.est_gb_per_day` < 10** (free-plan daily cap). Keep `scrape_interval_s` 30–60s.
6. **`collectors/*.env` labels match `bindplane/configurations.yaml` selectors** — each
   Configuration's `spec.selector.matchLabels` must be a subset of at least one collector's
   `OPAMP_LABELS`. BindPlane uses subset matching (extra labels on the collector are fine).
7. **No secrets committed.** Tokens come from `.env` / `secrets.auto.tfvars` (gitignored) only.

Run the **`bindplane-validate`** skill before any Azure spend — it checks 1–7 statically.

## BindPlane on the free plan (IMPORTANT)

The free plan **has full CLI + API access** (confirmed). Pipelines are applied automatically via
the **`bindplane` CLI** (v1.98.3+) — a **local prerequisite** on the operator's machine:

```
brew tap observiq/bindplane && brew install bindplane   # macOS
# or: https://docs.bindplane.observiq.com/docs/install-cli
```

How it works:
- `scripts/up.sh` calls `scripts/bp-apply.sh --demo <name>` after collectors are enrolled.
- `bp-apply.sh` substitutes `${DT_ENV_ID}` / `${DT_API_TOKEN}` via `sed` into a temp copy,
  then runs `bindplane --remote-url <url> --api-key <key> apply -f <file.yaml>`.
  Destinations are applied before Configurations (dependency order).
- After apply, rollout is triggered for each Configuration via:
  `bindplane rollout start <configuration-name>`
  This is best-effort — if it errors (no agents yet connected) the script warns and continues.
- The `bindplane/*.yaml` files are **apply-ready resources** (not blueprints). The `rollout.md` is
  the **optional live-demo runbook** — adding a processor in the UI and rolling it out fleet-wide.
- Both demos' Configurations coexist in the one project, matched by the `demo=<name>` label.
- Re-running `up.sh` is fully idempotent — `apply` updates existing resources.
- To remove BindPlane resources on teardown: `scripts/down.sh --purge-bindplane` (optional;
  configs persist by design and are re-applied on next `up.sh`).

**Per-device unified signals model:** each edge collector receives metrics+logs+traces (all OTLP)
from its assigned devices, then forwards to the gateway. Two Configurations per demo:
- `<demo>-gateway` selector `{role: gateway, demo: <demo>}` — owns the `dynatrace_otlp` destination
- `<demo>-edge`    selector `{role: edge,    demo: <demo>}` — forwards OTLP to the gateway

The managed `dynatrace_otlp` destination handles **delta temporality** internally — no
`cumulativetodelta` processor is required (and none is available in the catalog).

**Collector counts (free plan cap ≤ 10, one demo at a time):**
- `manufacturing`: 6 collectors (1 gateway + 5 edge lines)
- `networking`:    5 collectors (1 gateway + 4 edge device groups)

**`resource_detection_v2` detectors must be `[system]`** — `docker` is not a valid detector
in the current catalog (causes an "invalid" error on apply). Use only `system`.

**Required `.env` keys for pipeline apply:**
- `BP_API_KEY` — BindPlane API key (Settings > API Keys in the BindPlane UI)
- `BP_REMOTE_URL` — optional; defaults to `https://app.bindplane.com`

Without `BP_API_KEY`, `up.sh` warns and skips apply; collectors enroll but receive no pipeline.

## Architecture (how it fits together)

```
scripts/up.sh --demo <name> [--cloud azure|aws]
  → terraform apply -var demo=<name>   (reads demos/<name>/manifest.yaml via locals.tf)
      · --cloud azure (default) → terraform/azure/  → 1 Linux VM, single resource group
      · --cloud aws             → terraform/aws/    → 1 EC2 instance, VPC + IGW + SG + EIP
  → cloud-init (shared terraform/cloud-init.tftpl) installs docker + writes /opt/demo/.env
  → BDOT collectors enroll to BindPlane Cloud over OpAMP (endpoint+secret+labels)
  → simulators feed collectors; instrumented FastAPI app emits traces to the gateway collector
  → scripts/bp-apply.sh:
       bindplane apply -f destinations.yaml    (operator's machine → BindPlane Cloud)
       bindplane apply -f configurations.yaml
       bindplane rollout start <name>           (for each Configuration, best-effort)
  → BindPlane pushes pipelines to matching collectors (OpAMP heartbeat, ~60s)
  → gateway collector exports OTLP via dynatrace_otlp destination → Dynatrace
scripts/down.sh [--cloud ...]    → ssh-drain collectors (frees cap) → terraform destroy (atomic)
scripts/down.sh --purge-bindplane → also deletes BindPlane Configurations + Destinations
                                      (bindplane delete configuration <name> / delete destination <name>)
```

**Cloud credentials** — the scripts never read access keys from `.env`:
  · Azure: `az login` (azurerm provider uses the active CLI session).
  · AWS:   standard CLI credential chain — env vars, `~/.aws/credentials` (`aws configure`),
          `~/.aws/config` (`aws sso login --profile <name>`), or IAM role. Set `AWS_PROFILE`
          in `.env` if you use a named profile. `require_aws_cli` in `scripts/lib/common.sh`
          fails fast with `aws sts get-caller-identity` before any tf apply.

Only the **gateway** collector holds the Dynatrace token (via the `dynatrace_otlp` destination
managed in BindPlane); edge collectors forward OTLP to the gateway via `otlp_grpc` destination.

## Project agents & skills (`.claude/`)

- **agents/terraform-azure** — the Azure root (`terraform/azure/`) + modules + cloud-init. Keep it demo-agnostic.
- **agents/bindplane-pipeline** — `demos/*/bindplane/*.yaml` blueprints + rollout runbooks.
- **agents/otel-simulator** — Compose simulators + instrumented trace apps (3-signal contract).
- **skills/demo-scaffold** — generate a new `demos/<name>/` from `demos/_template/`.
- **skills/bindplane-validate** — static guardrail (rules 1–7 above) before spin-up.

The AWS root (`terraform/aws/`) mirrors the Azure root and is also demo-agnostic — same outputs
(`public_ip`, `admin_username`, `vm_name`, `demo`) so the scripts treat both clouds symmetrically.
When editing AWS Terraform, keep parity with the Azure module surface (same `name_suffix`
pattern, same `common_tags` map, same EIP/PIP semantics).

## House style

- Python simulators: small, single-purpose, stdlib + minimal deps, env-driven config, structured
  logging. OTel apps use the OTel SDK exporting OTLP to the local gateway collector.
- Terraform: one root in `terraform/`, demo-agnostic; per-demo data comes only from the manifest.
  `terraform fmt` before commit. Pin provider + module versions.
- Shell scripts: `set -euo pipefail`, source `scripts/lib/common.sh`, read manifest via `yq`.
- Never commit `*.tfvars` (except `*.tfvars.example`), `.env`, `*.tfstate*`, `.terraform/`.
