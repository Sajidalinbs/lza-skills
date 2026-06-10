#!/usr/bin/env python3
"""patch_scps.py — exempt the StackSets execution role in LZA SCP *source* files.

The #1 LZA pipeline failure: a customer-managed SCP denies an action without
exempting `stacksets-exec-*` (CloudFormation StackSets' service-managed
execution role), so Control Tower's account baselining gets an `explicit deny`
and the whole pipeline fails.

This walks every `*.json` SCP under a directory and ensures the principal
`arn:${PARTITION}:iam::*:role/stacksets-exec-*` is present in every
`Condition.ArnNotLike["aws:PrincipalArn"]` allow-list (the standard LZA pattern
for "deny everyone EXCEPT these roles").

Usage:
    python3 patch_scps.py service-control-policies/            # patch in place
    python3 patch_scps.py service-control-policies/ --dry-run  # show changes only

Commit the changed files and let the pipeline redeploy them. To also fix the
ALREADY-DEPLOYED policy content (when the pipeline re-attaches old content
faster than a deploy can fix it), use patch_deployed_scps.py.
"""
import argparse
import json
import pathlib
import sys

EXEMPT_ARN = "arn:${PARTITION}:iam::*:role/stacksets-exec-*"
PRINCIPAL_KEY = "aws:PrincipalArn"


def _as_list(v):
    return v if isinstance(v, list) else [v]


def patch_statement(stmt) -> bool:
    """Add EXEMPT_ARN to this statement's ArnNotLike[aws:PrincipalArn]. Returns True if changed."""
    cond = stmt.get("Condition")
    if not isinstance(cond, dict):
        return False
    changed = False
    for op in ("ArnNotLike", "ArnNotLikeIfExists"):
        block = cond.get(op)
        if not isinstance(block, dict) or PRINCIPAL_KEY not in block:
            continue
        arns = _as_list(block[PRINCIPAL_KEY])
        if EXEMPT_ARN not in arns:
            arns.append(EXEMPT_ARN)
            block[PRINCIPAL_KEY] = arns
            changed = True
    return changed


def patch_document(doc) -> bool:
    changed = False
    for stmt in _as_list(doc.get("Statement", [])):
        if isinstance(stmt, dict) and patch_statement(stmt):
            changed = True
    return changed


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="directory containing SCP *.json files (recursed)")
    ap.add_argument("--dry-run", action="store_true", help="report what would change, write nothing")
    args = ap.parse_args()

    root = pathlib.Path(args.path)
    if not root.exists():
        sys.exit(f"path not found: {root}")

    files = sorted(root.rglob("*.json"))
    if not files:
        sys.exit(f"no *.json files under {root}")

    patched = 0
    for f in files:
        try:
            doc = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            print(f"  SKIP (invalid JSON): {f} — {e}")
            continue
        if patch_document(doc):
            patched += 1
            if args.dry_run:
                print(f"  WOULD PATCH: {f}")
            else:
                f.write_text(json.dumps(doc, indent=2) + "\n")
                print(f"  PATCHED: {f}")
        else:
            print(f"  ok (already exempt or no ArnNotLike): {f}")

    verb = "would patch" if args.dry_run else "patched"
    print(f"\n{verb} {patched}/{len(files)} file(s).")


if __name__ == "__main__":
    main()
