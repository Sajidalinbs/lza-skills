#!/usr/bin/env bash
# bulk_suppress.sh — flip EXISTING active NEW findings to SUPPRESSED for a given
# control (optionally scoped to an ARN substring). Automation rules are NOT
# retroactive, so use this once after deploying/fixing a suppression rule to
# clear the backlog instead of waiting ~12-24h for re-evaluation.
#
# Run with DELEGATED ADMIN (Audit) credentials, HomeRegion.
# Usage: ./bulk_suppress.sh <region> <control-id> [resource-id-substring] [--apply]
#   ./bulk_suppress.sh eu-central-1 StepFunctions.1 CreateOrganizationAccounts          # dry-run
#   ./bulk_suppress.sh eu-central-1 StepFunctions.1 CreateOrganizationAccounts --apply
set -euo pipefail

REGION="${1:?usage: bulk_suppress.sh <region> <control-id> [arn-substring] [--apply]}"
CONTROL="${2:?control id required, e.g. StepFunctions.1}"
SUBSTR="${3:-}"
APPLY="${4:-}"
[ "${SUBSTR:-}" = "--apply" ] && { APPLY="--apply"; SUBSTR=""; }

FILTER="{\"ComplianceSecurityControlId\":[{\"Value\":\"$CONTROL\",\"Comparison\":\"EQUALS\"}],\"RecordState\":[{\"Value\":\"ACTIVE\",\"Comparison\":\"EQUALS\"}],\"WorkflowStatus\":[{\"Value\":\"NEW\",\"Comparison\":\"EQUALS\"}]}"

# Collect "Id<TAB>ProductArn" rows, filtered by ARN substring if given.
mapfile -t ROWS < <(aws securityhub get-findings --region "$REGION" --filters "$FILTER" \
  --max-items 400 \
  --query "Findings[?contains(Resources[0].Id, \`${SUBSTR}\`)].[Id,ProductArn]" \
  --output text 2>/dev/null)

echo "Matched ${#ROWS[@]} NEW findings for $CONTROL${SUBSTR:+ (ARN ~ $SUBSTR)}"
[ "${#ROWS[@]}" -eq 0 ] && { echo "nothing to do"; exit 0; }

if [ "$APPLY" != "--apply" ]; then
  printf '%s\n' "${ROWS[@]}" | awk '{print $1}' | head -20
  echo "... DRY RUN. Re-run with --apply as the last arg to suppress these."
  exit 0
fi

# batch-update-findings accepts up to 100 identifiers per call — chunk it.
IDENT="[]"; n=0
flush() {
  [ "$n" -eq 0 ] && return
  aws securityhub batch-update-findings --region "$REGION" --finding-identifiers "$IDENT" \
    --workflow Status=SUPPRESSED \
    --note "Text=Bulk-suppressed (matches deployed automation rule for $CONTROL),UpdatedBy=lza-security-remediate" \
    --query 'length(ProcessedFindings)' --output text
  IDENT="[]"; n=0
}
for row in "${ROWS[@]}"; do
  ID=$(printf '%s' "$row" | awk '{print $1}')
  PA=$(printf '%s' "$row" | awk '{print $2}')
  IDENT=$(python3 - "$IDENT" "$ID" "$PA" <<'PY'
import sys,json
arr=json.loads(sys.argv[1]); arr.append({"Id":sys.argv[2],"ProductArn":sys.argv[3]}); print(json.dumps(arr))
PY
)
  n=$((n+1))
  [ "$n" -eq 100 ] && flush
done
flush
echo "done."
