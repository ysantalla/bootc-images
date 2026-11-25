#!/usr/bin/env python3
"""Deletes old builds of an image from GHCR. Prints what it would do unless --delete is given.

Every build leaves a dated tag (45-20261201), the signature of its digest
(sha256-<digest>.sig), and, when a tag moves to a newer build the same day, an
untagged manifest. Nothing removed them.

Kept:
  - every version with a tag that is not a date or a signature: latest, staging, 45
  - dated tags of the last KEEP_DAYS days, and always the newest KEEP_MIN of them,
    so that `bootc switch ...:45-20261201` can still go back
  - the signature of every version that is kept
Deleted, once older than GRACE_DAYS, so that a build in progress is never touched:
  - older dated tags, untagged manifests, and signatures of what is gone

Needs `gh`, with a token that may delete package versions.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

KEEP_DAYS = 30
KEEP_MIN = 7
GRACE_DAYS = 2
DATED = re.compile(r"\d+-(\d{8})")
SIGNATURE = re.compile(r"sha256-([0-9a-f]{64})\.sig")


def gh(*args: str) -> str:
    return subprocess.run(["gh", "api", *args], check=True, capture_output=True, text=True).stdout


def versions(owner: str, package: str) -> list[dict]:
    out = gh("--paginate", f"users/{owner}/packages/container/{package}/versions?per_page=100",
             "--jq", ".[] | {id, name, created_at, tags: .metadata.container.tags}")
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def plan(found: list[dict], now: datetime) -> tuple[list[dict], list[dict]]:
    """Split the versions into those to keep and those to delete."""
    def created(v: dict) -> datetime:
        return datetime.fromisoformat(v["created_at"].replace("Z", "+00:00"))

    def date_of(tag: str) -> datetime | None:
        match = DATED.fullmatch(tag)
        try:
            return datetime.strptime(match.group(1), "%Y%m%d").replace(tzinfo=timezone.utc) if match else None
        except ValueError:
            return None

    dated = sorted({tag for v in found for tag in v["tags"] if date_of(tag)}, key=date_of, reverse=True)
    recent = {tag for tag in dated if now - date_of(tag) <= timedelta(days=KEEP_DAYS)} | set(dated[:KEEP_MIN])
    young = now - timedelta(days=GRACE_DAYS)

    keep_digests = set()
    signatures = []
    for v in found:
        if any(SIGNATURE.fullmatch(tag) for tag in v["tags"]):
            signatures.append(v)
            continue
        other = [tag for tag in v["tags"] if not date_of(tag)]
        if other or any(tag in recent for tag in v["tags"]) or created(v) > young:
            keep_digests.add(v["name"])
    keep, delete = [], []
    for v in found:
        if v in signatures:
            signed = {"sha256:" + SIGNATURE.fullmatch(tag).group(1) for tag in v["tags"] if SIGNATURE.fullmatch(tag)}
            (keep if signed & keep_digests or created(v) > young else delete).append(v)
        else:
            (keep if v["name"] in keep_digests else delete).append(v)
    return keep, delete


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("owner")
    parser.add_argument("package", nargs="+")
    parser.add_argument("--delete", action="store_true", help="delete; without it, only say what would go")
    args = parser.parse_args()
    now = datetime.now(timezone.utc)
    failed = False
    for package in args.package:
        found = versions(args.owner, package)
        keep, delete = plan(found, now)
        kept_tags = sorted(tag for v in keep for tag in v["tags"] if not SIGNATURE.fullmatch(tag))
        print(f"{package}: {len(found)} versions, keep {len(keep)}, delete {len(delete)}")
        print(f"  tags kept: {' '.join(kept_tags)}")
        for v in sorted(delete, key=lambda v: v["created_at"]):
            what = " ".join(v["tags"]) or "(untagged)"
            print(f"  {'delete' if args.delete else 'would delete'} {v['created_at'][:10]} {v['name'][:19]} {what[:40]}")
            if args.delete:
                try:
                    gh("-X", "DELETE", f"users/{args.owner}/packages/container/{package}/versions/{v['id']}")
                except subprocess.CalledProcessError as error:
                    print(f"    failed: {error.stderr.strip()}", file=sys.stderr)
                    failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
