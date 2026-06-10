#!/usr/bin/env bash
# fetch_baseline.sh — seed an LZA config repo from the OFFICIAL AWS baseline.
#
# Don't write LZA config from scratch. AWS ships a ready, opinionated baseline —
# the "LZA Universal Configuration" (formerly the sample-configurations folder) —
# with the six YAML files PLUS all the supporting policy folders (SCPs, RCPs,
# declarative policies, tagging, backup, dynamic-partitioning, ssm-documents…).
# This pulls that baseline into your config repo so you only have to CUSTOMIZE it.
#
# Source: https://github.com/aws/lza-universal-configuration
#   modules/base/default            -> the 6 YAML + policy folders (always copied)
#   modules/network/hub-and-spoke   -> TGW hub-and-spoke networking (optional)
#   modules/network/shared-vpc      -> Shared VPC networking (optional)
#
# IMPORTANT — networking is NOT taken from the baseline by default:
#   * We do NOT use IPAM — VPC/subnet CIDRs are explicit (from the intake planner).
#   * We do NOT deploy a DNS hub VPC or a central interface-endpoints VPC.
#   The hub-and-spoke / shared-vpc modules bundle IPAM + DNS + endpoints VPCs, so the
#   DEFAULT network-model is 'none'. We copy only base/default (org/security/governance)
#   and build network-config.yaml from intake (plan_subnets.py -> network-config.snippet.yaml).
#   If you do pass a network model, strip its IPAM, DNS-VPC and endpoints-VPC blocks afterward.
#
# Usage:
#   ./fetch_baseline.sh <target-config-dir> [network-model] [uc-tag]
#     network-model : none | hub-and-spoke | shared-vpc   (default: none)
#     uc-tag        : Universal Config release tag         (default: v1.2.0)
#
# Example:
#   ./fetch_baseline.sh ../acme-lza-config            # base only; network from intake
#   ./fetch_baseline.sh ../acme-lza-config hub-and-spoke  # reference only (then strip DNS/endpoints/IPAM)
#
# After this, the baseline ships with these accounts/OUs (you then customize):
#   Accounts : Management, LogArchive, Audit (mandatory) + Network, SharedServices, Perimeter
#   OUs      : Security, Infrastructure, Suspended(ignore), Workloads/{Sandbox,Dev,Test,Prod}
#   Prefix   : AWSAccelerator (replacements-config.yaml) — change BEFORE first deploy
set -euo pipefail

TARGET="${1:?usage: fetch_baseline.sh <target-config-dir> [network-model] [uc-tag]}"
NET_MODEL="${2:-none}"
UC_TAG="${3:-v1.2.0}"
REPO="https://github.com/aws/lza-universal-configuration"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $REPO @ $UC_TAG ..." >&2
git clone --depth 1 --branch "$UC_TAG" "$REPO" "$TMP/uc" >/dev/null 2>&1 || {
  echo "tag $UC_TAG not found; cloning default branch instead" >&2
  git clone --depth 1 "$REPO" "$TMP/uc" >/dev/null 2>&1
}

BASE="$TMP/uc/modules/base/default"
[[ -d "$BASE" ]] || { echo "baseline path missing in repo: modules/base/default" >&2; exit 1; }

mkdir -p "$TARGET"
echo "Copying base/default -> $TARGET" >&2
cp -R "$BASE/." "$TARGET/"

if [[ "$NET_MODEL" != "none" ]]; then
  NET="$TMP/uc/modules/network/$NET_MODEL"
  if [[ -d "$NET" ]]; then
    echo "Overlaying network model '$NET_MODEL' -> $TARGET" >&2
    cp -R "$NET/." "$TARGET/"
  else
    echo "WARNING: network model '$NET_MODEL' not found; skipping" >&2
  fi
fi

cat >&2 <<EOF

✓ Baseline copied to: $TARGET
  Universal Config tag: $UC_TAG   network model: $NET_MODEL

NEXT — customize (see /lza-configure):
  1. replacements-config.yaml : set AcceleratorPrefix, HomeRegion/EnabledRegions, emails, TGW ASN
  2. accounts-config.yaml     : real emails; add customer workload accounts
                                (or replace with the intake-generated accounts-config.yaml)
  3. organization-config.yaml : adjust OUs to your design
                                (or use the intake-generated OU block)
  4. network-config.yaml      : paste intake network-config.snippet.yaml under your VPCs
  5. Do NOT deploy until AcceleratorPrefix is final (it locks on first run).
EOF
