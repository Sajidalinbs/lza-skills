#!/usr/bin/env bash
# find_precheck_failure.sh — surface the Control Tower PrecheckOrganizationalUnit
# event and its `failedPrechecks` array, the most useful artifact for diagnosing
# a "Baseline operation FAILED" pipeline error.
#
# Usage:
#   ./find_precheck_failure.sh [minutes-back]      # default: 120 minutes
#
# Requires: awscli v2, jq. Run with management-account credentials in the
# HomeRegion (CloudTrail management events are regional).
set -euo pipefail

MINUTES="${1:-120}"
EVENT_NAME="PrecheckOrganizationalUnit"

# Portable "MINUTES ago" for both GNU and BSD/macOS date.
if date -u -d "@0" >/dev/null 2>&1; then
  START="$(date -u -d "-${MINUTES} minutes" +%Y-%m-%dT%H:%M:%SZ)"   # GNU
else
  START="$(date -u -v-"${MINUTES}"M +%Y-%m-%dT%H:%M:%SZ)"           # BSD/macOS
fi

echo "Looking for ${EVENT_NAME} events since ${START} ..." >&2

aws cloudtrail lookup-events \
  --lookup-attributes "AttributeKey=EventName,AttributeValue=${EVENT_NAME}" \
  --start-time "${START}" \
  --max-results 10 \
  --query 'Events[].CloudTrailEvent' \
  --output text \
| jq -rc 'fromjson
    | { time: .eventTime,
        sourceOU: (.requestParameters.organizationalUnitId // .requestParameters.targetIdentifier // "?"),
        failedPrechecks: (.responseElements.failedPrechecks // .serviceEventDetails.failedPrechecks // []) }
    | select(.failedPrechecks | length > 0)'

echo "(If nothing printed, widen the window: ./find_precheck_failure.sh 360)" >&2
