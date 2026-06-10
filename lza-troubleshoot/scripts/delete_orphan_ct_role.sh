#!/usr/bin/env bash
# delete_orphan_ct_role.sh — remove an orphan AWSControlTowerExecution role from a
# member account so Control Tower can recreate it cleanly.
#
# Symptom this fixes:
#   "Resource of type 'AWS::IAM::Role' with identifier 'AWSControlTowerExecution'
#    already exists" — left behind by a previously partially-failed CT deploy.
#
# Usage:
#   ./delete_orphan_ct_role.sh <member-account-id> [--yes]
#
# Run with MANAGEMENT-account credentials; it assumes into the member account via
# the AWSControlTowerExecution role itself. Without --yes it stops after showing
# what it would delete (dry run).
#
# Requires: awscli v2, jq.
set -euo pipefail

ACCOUNT_ID="${1:-}"
CONFIRM="${2:-}"
ROLE="AWSControlTowerExecution"

if [[ -z "$ACCOUNT_ID" ]]; then
  echo "usage: $0 <member-account-id> [--yes]" >&2
  exit 1
fi

echo "Assuming ${ROLE} in ${ACCOUNT_ID} ..." >&2
CREDS="$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE}" \
  --role-session-name "orphan-ct-role-cleanup" \
  --query 'Credentials' --output json)"

export AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"$CREDS")"
export AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$CREDS")"
export AWS_SESSION_TOKEN="$(jq -r .SessionToken <<<"$CREDS")"

echo "Attached managed policies on ${ROLE}:" >&2
ATTACHED="$(aws iam list-attached-role-policies --role-name "$ROLE" \
  --query 'AttachedPolicies[].PolicyArn' --output text || true)"
echo "  ${ATTACHED:-<none>}" >&2

INLINE="$(aws iam list-role-policies --role-name "$ROLE" \
  --query 'PolicyNames' --output text || true)"
echo "Inline policies: ${INLINE:-<none>}" >&2

if [[ "$CONFIRM" != "--yes" ]]; then
  echo "" >&2
  echo "DRY RUN — would detach the above and delete role ${ROLE} in ${ACCOUNT_ID}." >&2
  echo "Re-run with --yes to perform the deletion." >&2
  exit 0
fi

for arn in $ATTACHED; do
  echo "Detaching ${arn} ..." >&2
  aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$arn"
done
for name in $INLINE; do
  echo "Deleting inline policy ${name} ..." >&2
  aws iam delete-role-policy --role-name "$ROLE" --policy-name "$name"
done

echo "Deleting role ${ROLE} ..." >&2
aws iam delete-role --role-name "$ROLE"
echo "Done. Re-run the LZA pipeline; Control Tower will recreate ${ROLE}." >&2
