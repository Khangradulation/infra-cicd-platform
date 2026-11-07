#!/usr/bin/env python3
"""Summarise `terraform show -json <plan>` WITHOUT attribute values.

Prints Markdown (resource addresses + actions + counts) that is safe to post to
a PR or job summary, and a stable fingerprint of the change set so the apply
job can prove it is applying exactly what was reviewed.

Usage:
  terraform show -json tfplan | scripts/tf-plan-summary.py --env dev --markdown out.md --fingerprint-file fp.txt
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter

SYMBOL = {
    "create": "+ create",
    "update": "~ update",
    "delete": "- destroy",
    "replace": "-/+ replace",
    "read": "<= read",
}


def classify(actions: list[str]) -> str:
    if actions == ["no-op"]:
        return "no-op"
    if "create" in actions and "delete" in actions:
        return "replace"
    return actions[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True)
    ap.add_argument("--markdown", required=True)
    ap.add_argument("--fingerprint-file", required=True)
    args = ap.parse_args()

    plan = json.load(sys.stdin)
    changes = []
    for rc in plan.get("resource_changes", []):
        kind = classify(rc["change"]["actions"])
        if kind in ("no-op", "read"):
            continue
        changes.append((rc["address"], kind))
    changes.sort()

    drift = [d["address"] for d in plan.get("resource_drift", [])]
    output_changes = sorted(
        name for name, oc in (plan.get("output_changes") or {}).items() if oc.get("actions") != ["no-op"]
    )

    counts = Counter(kind for _, kind in changes)
    fingerprint = hashlib.sha256("\n".join(f"{a} {k}" for a, k in changes).encode()).hexdigest()

    lines = [f"### Terraform plan: `{args.env}`", ""]
    if not changes:
        lines.append("**No infrastructure changes.**")
    else:
        lines.append(
            f"**{counts['create']} to add, {counts['update']} to change, "
            f"{counts['delete']} to destroy, {counts['replace']} to replace.**"
        )
        if counts["delete"] or counts["replace"]:
            lines += ["", "> [!WARNING]", "> This plan destroys or replaces resources. Review carefully."]
        lines += ["", "<details><summary>Resource changes</summary>", "", "| Action | Address |", "|---|---|"]
        lines += [f"| `{SYMBOL.get(k, k)}` | `{a}` |" for a, k in changes]
        lines += ["", "</details>"]
    if drift:
        lines += ["", f"Drift detected outside Terraform on {len(drift)} resource(s): "
                  + ", ".join(f"`{d}`" for d in drift[:20])]
    if output_changes:
        lines += ["", "Outputs changing: " + ", ".join(f"`{o}`" for o in output_changes)]
    lines += ["", f"<sub>Change-set fingerprint `{fingerprint[:16]}`. Attribute values are deliberately omitted.</sub>", ""]

    with open(args.markdown, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    with open(args.fingerprint_file, "w", encoding="utf-8") as fh:
        fh.write(fingerprint)
    print(f"has_changes={'true' if changes else 'false'}")
    print(f"fingerprint={fingerprint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
