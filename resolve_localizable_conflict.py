#!/usr/bin/env python3
"""
Resolves the Localizable.xcstrings conflict from merging upstream/dev (this round).

Run from the Trio repo root, AFTER `git merge upstream/dev` (or GitHub Desktop's
"Merge into current branch") has reported a conflict ONLY in
Trio/Sources/Localizations/Main/Localizable.xcstrings. If other files are also
conflicted, stop and get a fresh look instead of running this.

Both conflict blocks are false alarms from git's line-based diff getting confused by
this file's repetitive JSON structure -- neither is a real edit clash:

  - Block 1: your branch's new "1 chart"/"1 hour" string entries happen to sit right
    after a "0.5 U and over" translation upstream tweaked (Chinese: "0.5 U 以上" ->
    "0.5 U 及以上"). Resolution: take upstream's corrected translation, keep
    everything your branch added after it.
  - Block 2: your branch's "Daily"/"Dana(RS/-i)" entries don't exist on upstream's
    side at all here (empty). Resolution: just keep your branch's content.

This resolves by exact line position (not text matching), since the file is ~327k
lines with a lot of near-identical repeated structure that makes plain text search
unreliable. It re-validates the result as JSON afterward, so if this script succeeds
the file is guaranteed structurally valid.
"""
import json
import subprocess
import sys

PATH = "Trio/Sources/Localizations/Main/Localizable.xcstrings"


def main():
    status = subprocess.run(
        ["git", "status", "--short"], capture_output=True, text=True, check=True
    ).stdout
    unmerged = [line[3:] for line in status.splitlines() if line.startswith("UU ")]

    unexpected = [f for f in unmerged if f != PATH]
    if unexpected:
        print("Found unexpected conflicts beyond Localizable.xcstrings:")
        for f in unexpected:
            print(f"  {f}")
        print("Stopping -- this needs a fresh look, don't resolve blindly.")
        sys.exit(1)

    if not unmerged:
        print(f"No conflict in {PATH}. Nothing to do.")
        sys.exit(0)

    with open(PATH, encoding="utf-8") as f:
        lines = f.readlines()

    marker_lines = [
        i for i, line in enumerate(lines)
        if line.startswith("<<<<<<<") or line.startswith("=======") or line.startswith(">>>>>>>")
    ]
    if len(marker_lines) != 6:
        print(f"Expected exactly 2 conflict blocks (6 marker lines), found {len(marker_lines)}.")
        print("The conflict shape differs from what this script expects -- stopping, don't guess.")
        sys.exit(1)

    b1_start, b1_mid, b1_end, b2_start, b2_mid, b2_end = marker_lines

    # Sanity-check the content matches what this script expects before touching anything.
    if lines[b1_start + 1].strip() != '"value" : "0.5 U 以上"':
        print("Block 1 content doesn't match expectations -- stopping, don't guess.")
        sys.exit(1)
    if lines[b1_mid + 1].strip() != '"value" : "0.5 U 及以上"':
        print("Block 1 upstream content doesn't match expectations -- stopping, don't guess.")
        sys.exit(1)
    if lines[b2_mid + 1] != lines[b2_end]:
        print("Block 2 upstream side isn't empty as expected -- stopping, don't guess.")
        sys.exit(1)

    head1 = lines[b1_start + 1:b1_mid]
    upstream1 = lines[b1_mid + 1:b1_end]
    resolved1 = upstream1 + head1[1:]  # swap just the first (changed) line

    head2 = lines[b2_start + 1:b2_mid]
    resolved2 = head2  # upstream side is empty here; keep our content as-is

    # Apply from the bottom up so earlier line indices stay valid.
    new_lines = lines[:b2_start] + resolved2 + lines[b2_end + 1:]
    new_lines = new_lines[:b1_start] + resolved1 + new_lines[b1_end + 1:]

    content = "".join(new_lines)
    if "<<<<<<<" in content or ">>>>>>>" in content:
        print("Conflict markers still remain after resolving -- stopping.")
        sys.exit(1)

    with open(PATH, "w", encoding="utf-8") as f:
        f.write(content)

    # Re-validate as JSON -- if this fails, something about the file structure
    # doesn't match what this script assumed, and it needs a fresh look.
    with open(PATH, encoding="utf-8") as f:
        json.load(f)

    subprocess.run(["git", "add", PATH], check=True)
    print("Resolved. Re-validated as JSON successfully.")
    print("Run 'git status' to confirm, then 'git commit --no-edit'.")


if __name__ == "__main__":
    main()
