"""Render Mnemosyne memories as Obsidian markdown notes.

Deterministic replacement for integrations/obsidian-mnemosyne (the upstream
"Mnemosyne Sync" plugin), which does not work: its embedded Python is
mis-indented and fails to parse, it calls .get() on a sqlite3.Row, and it looks
for <bank>.db when the file is mnemosyne.db.

Reads through `mnemosyne export` rather than opening the SQLite file directly,
so this is not coupled to the schema - and so it never touches the sqlite-vec
vec0 virtual tables, which is the other thing that breaks naive readers.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Highest-confidence tier first: an id present in several tiers is rendered once,
# from the first tier that carries it.
TIERS = ("working_memory", "episodic_memory", "legacy_memories")

FM_RE = re.compile(r"\A---\n(.*?)\n---\n\n?(.*)\Z", re.DOTALL)
SHA_RE = re.compile(r"^content_sha:\s*\"?([0-9a-f]{64})\"?\s*$", re.MULTILINE)
UNSAFE = re.compile(r"[^A-Za-z0-9_.-]")


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def is_assistant(row: dict) -> bool:
    return str(row.get("source") or "").lower().endswith("assistant") or str(
        row.get("content") or ""
    ).startswith("[ASSISTANT]")


def quote(value) -> str:
    """Minimal YAML scalar quoting - frontmatter values here are ids, dates,
    numbers and short source strings, never multiline."""
    s = "" if value is None else str(value)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def render(row: dict, tier: str, synced: str) -> str:
    content = (row.get("content") or "").strip()
    fields = {
        "id": row.get("id"),
        "tier": tier,
        "source": row.get("source") or "unknown",
        "scope": row.get("scope") or "",
        "session_id": row.get("session_id") or "",
        "timestamp": str(row.get("timestamp") or "")[:19],
        "importance": row.get("importance", 0),
        "content_sha": sha(content),
        "synced": synced,
    }
    lines = ["---"]
    lines += [f"{k}: {quote(v)}" for k, v in fields.items()]
    lines += ["tags:", "  - mnemosyne", f"  - {tier.replace('_', '-')}", "---", ""]
    return "\n".join(lines) + content + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault", required=True)
    ap.add_argument("--folder", default="Mnemosyne")
    ap.add_argument("--mnemosyne", default="mnemosyne", help="mnemosyne CLI to export with")
    ap.add_argument("--include-assistant", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    out_dir = Path(args.vault) / args.folder
    # Never create the vault itself: a mistyped --vault should fail loudly
    # rather than quietly scattering notes into a new directory tree.
    if not Path(args.vault).is_dir():
        print(f"vault not found: {args.vault}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        dump = Path(tmp) / "export.json"
        proc = subprocess.run(
            [args.mnemosyne, "export", str(dump)],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not dump.exists():
            print(proc.stderr.strip() or "mnemosyne export failed", file=sys.stderr)
            return 1
        data = json.loads(dump.read_text())

    synced = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    written = updated = skipped = unchanged = 0
    seen: set[str] = set()

    for tier in TIERS:
        for row in data.get(tier) or []:
            mid = str(row.get("id") or "")
            if not mid or mid in seen:
                continue
            seen.add(mid)
            if is_assistant(row) and not args.include_assistant:
                continue
            if not (row.get("content") or "").strip():
                continue

            body = render(row, tier, synced)
            path = out_dir / (UNSAFE.sub("_", mid) + ".md")

            if path.exists():
                existing = path.read_text(encoding="utf-8", errors="replace")
                m = FM_RE.match(existing)
                stored = SHA_RE.search(m.group(1)) if m else None
                # A note whose body no longer hashes to the content_sha it was
                # written with has been edited by hand. Leave it: the vault is
                # the human's copy, and losing an edit is worse than a stale
                # note. Delete the file to force a re-render.
                if not m or not stored or sha(m.group(2).strip()) != stored.group(1):
                    skipped += 1
                    continue
                if stored.group(1) == sha((row.get("content") or "").strip()):
                    unchanged += 1
                    continue
                action = "update"
            else:
                action = "write"

            if args.dry_run:
                print(f"  would {action}: {path.relative_to(args.vault)}")
            else:
                out_dir.mkdir(parents=True, exist_ok=True)
                # Write-then-rename so a vault sync client never observes a
                # half-written note.
                tmp_path = path.with_suffix(".md.tmp")
                tmp_path.write_text(body, encoding="utf-8")
                os.replace(tmp_path, path)
            written += action == "write"
            updated += action == "update"

    verb = "would sync" if args.dry_run else "synced"
    print(
        f"mnemosyne -> {out_dir}: {verb} {written} new, {updated} updated, "
        f"{unchanged} unchanged, {skipped} skipped (hand-edited)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
