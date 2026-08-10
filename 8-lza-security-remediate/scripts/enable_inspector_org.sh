#!/usr/bin/env bash
# enable_inspector_org.sh — enable Amazon Inspector organization-wide.
# LZA has no native Inspector config, so this is an operational change — record
# it on the risk register as config drift from the repo.
#
# Usage: ./enable_inspector_org.sh <mgmt-profile> <audit-account-id> <region> [scan-types]
#   ./enable_inspector_org.sh customer-mgmt 111122223333 eu-central-1
#   scan-types default: "ec2=true,ecr=true,lambda=true,lambdaCode=true"
#   (drop lambdaCode if cost-sensitive — it's the biggest billing driver)
set -euo pipefail

MGMT_PROFILE="${1:?usage: enable_inspector_org.sh <mgmt-profile> <audit-acct-id> <region> [scan-types]}"
AUDIT="${2:?audit account id required}"
REGION="${3:?region required}"
AUTO="${4:-ec2=true,ecr=true,lambda=true,lambdaCode=true}"
# Resource types derived from AUTO for the explicit enable calls:
RTYPES="EC2 ECR LAMBDA LAMBDA_CODE"

echo "==> [mgmt] set Inspector delegated admin = $AUDIT"
aws inspector2 enable-delegated-admin-account --delegated-admin-account-id "$AUDIT" \
  --region "$REGION" --profile "$MGMT_PROFILE" || echo "   (already delegated?)"

echo "==> assume into Audit ($AUDIT) for org configuration"
CREDS=$(aws sts assume-role --profile "$MGMT_PROFILE" \
  --role-arn "arn:aws:iam::${AUDIT}:role/AWSControlTowerExecution" \
  --role-session-name inspector-enable --query Credentials --output json)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["AccessKeyId"])')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["SecretAccessKey"])')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["SessionToken"])')
unset AWS_PROFILE

echo "==> [audit] enable Inspector on the delegated admin itself"
aws inspector2 enable --resource-types $RTYPES --account-ids "$AUDIT" --region "$REGION" \
  --query 'accounts[].{Acct:accountId,Status:status}' --output text

echo "==> [audit] org auto-enable = $AUTO (covers FUTURE accounts)"
aws inspector2 update-organization-configuration --auto-enable "$AUTO" --region "$REGION" \
  --query 'autoEnable' --output json

echo "==> [audit] associate + enable EXISTING member accounts"
# (auto-enable does NOT retroactively enable existing accounts — they must be associated first,
#  otherwise 'enable' returns ACCESS_DENIED.)
MEMBERS=$(aws organizations list-accounts --profile "$MGMT_PROFILE" \
  --query "Accounts[?Status=='ACTIVE' && Id!='$AUDIT'].Id" --output text)
for A in $MEMBERS; do
  aws inspector2 associate-member --account-id "$A" --region "$REGION" >/dev/null 2>&1 \
    && echo "   associated $A" || echo "   (skip $A — mgmt or already member)"
done

echo "==> member status:"
aws inspector2 list-members --region "$REGION" \
  --query 'members[].{Acct:accountId,Rel:relationshipStatus}' --output text

echo
echo "NOTE: the MANAGEMENT account self-manages — enable it from a management-account identity:"
echo "  aws inspector2 enable --resource-types $RTYPES --account-ids <MGMT_ACCT> --region $REGION --profile $MGMT_PROFILE"
echo "Resolves Inspector.1/.2/.3/.4 once initial scans complete. Inspector is billable per resource."
