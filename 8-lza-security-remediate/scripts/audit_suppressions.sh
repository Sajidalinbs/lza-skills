#!/usr/bin/env bash
# audit_suppressions.sh — show, per control, how many active findings are
# SUPPRESSED vs NEW vs RESOLVED in the Security Hub aggregator (Audit account).
# Reveals which suppression automation rules actually fire.
#
# Run with credentials for the DELEGATED ADMIN (Audit) account, HomeRegion.
# Usage: ./audit_suppressions.sh <region> [control-id ...]
#   ./audit_suppressions.sh eu-central-1
#   ./audit_suppressions.sh eu-central-1 Lambda.3 S3.20 StepFunctions.1
set -euo pipefail

REGION="${1:?usage: audit_suppressions.sh <region> [control-id ...]}"; shift || true

# Default control set = the controls this skill typically suppresses.
CONTROLS=("$@")
if [ "${#CONTROLS[@]}" -eq 0 ]; then
  CONTROLS=(CloudWatch.15 DynamoDB.4 DynamoDB.6 EC2.10 EC2.23 EC2.56 EC2.57 EC2.58 EC2.60 \
            EC2.172 Kinesis.3 KMS.1 KMS.2 Lambda.3 Lambda.7 S3.6 S3.7 S3.9 S3.11 S3.15 \
            S3.17 S3.20 IAM.21 IAM.22 StepFunctions.1 Backup.1)
fi

printf '%-18s %s\n' "CONTROL" "STATUS COUNTS (active findings)"
printf '%-18s %s\n' "-------" "------------------------------"
for C in "${CONTROLS[@]}"; do
  COUNTS=$(aws securityhub get-findings --region "$REGION" \
    --filters "{\"ComplianceSecurityControlId\":[{\"Value\":\"$C\",\"Comparison\":\"EQUALS\"}],\"RecordState\":[{\"Value\":\"ACTIVE\",\"Comparison\":\"EQUALS\"}]}" \
    --max-items 400 \
    --query 'Findings[].Workflow.Status' --output text 2>/dev/null \
    | tr '\t' '\n' | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')
  printf '%-18s %s\n' "$C" "${COUNTS:-<none>}"
done

echo
echo "Reading: only SUPPRESSED/RESOLVED => rule works. Any NEW that should be covered => rule"
echo "not matching (see SKILL.md §2 — AcceleratorPrefix vs AWSAccelerator / null finding tags)."
