#!/usr/bin/env python3
"""
Resolves the conflicts from merging feat/algorithm-adjustments-stats into dev:

1. Trio.xcodeproj/project.pbxproj -- feat/algorithm-adjustments-stats added a
   PBXFileReference entry (PlacementLogStorage.swift) that dev doesn't have.
   Keeps both sides' lines (empty + the new entry = just the new entry).

2. resolve_dev_merge_v3.sh -- a throwaway helper script from an earlier sync
   round that got accidentally committed to both branches independently
   (add/add conflict). It's not part of the app; this just removes it.

Run this from the Trio repo root, after `git merge origin/feat/algorithm-
adjustments-stats` has reported conflicts. Many files may flash "CONFLICT"
in the merge output and then resolve themselves automatically via git's
rename-aware merge -- that's expected and fine. Only trust `git status`
for what's ACTUALLY still unmerged afterward. If `git status` shows
anything unmerged beyond these two files, stop and get a fresh look
instead of running this.
"""
import re
import subprocess
import sys

PBXPROJ = "Trio.xcodeproj/project.pbxproj"
HELPER_SCRIPT = "resolve_dev_merge_v3.sh"
EXPECTED = {PBXPROJ, HELPER_SCRIPT}

CONFLICT_RE = re.compile(
    r"<<<<<<< HEAD\n?(.*?)\n?=======\n?(.*?)\n?>>>>>>> [^\n]+\n", re.DOTALL
)


def resolve_pbxproj(path):
    with open(path) as f:
        content = f.read()

    def keep_both(m):
        ours, theirs = m.group(1), m.group(2)
        parts = [p for p in (ours, theirs) if p]
        return ("\n".join(parts) + "\n") if parts else ""

    resolved, n = CONFLICT_RE.subn(keep_both, content)
    if n == 0:
        return False
    with open(path, "w") as f:
        f.write(resolved)
    print(f"{path}: resolved {n} block(s) (kept both sides' entries)")
    return True


def main():
    status = subprocess.run(
        ["git", "status", "--short"], capture_output=True, text=True, check=True
    ).stdout
    unmerged = set()
    for line in status.splitlines():
        code, path = line[:2], line[3:]
        if "U" in code or code == "AA":
            unmerged.add(path.strip('"'))

    unexpected = unmerged - EXPECTED
    if unexpected:
        print("Found unexpected conflicts beyond the two expected files:")
        for f in sorted(unexpected):
            print(f"  {f}")
        print("Stopping -- this needs a fresh look, don't resolve blindly.")
        sys.exit(1)

    if not unmerged:
        print("No conflicts in the expected files. Nothing to do.")
        sys.exit(0)

    if PBXPROJ in unmerged:
        if resolve_pbxproj(PBXPROJ):
            with open(PBXPROJ) as fh:
                if re.search(r"^(<{7}|={7}|>{7})", fh.read(), re.MULTILINE):
                    print(f"{PBXPROJ}: conflict markers still remain -- stopping.")
                    sys.exit(1)
            subprocess.run(["git", "add", PBXPROJ], check=True)

    if HELPER_SCRIPT in unmerged:
        subprocess.run(["git", "rm", "-f", HELPER_SCRIPT], check=True)
        print(f"{HELPER_SCRIPT}: removed (throwaway helper script, not app code)")

    print("\nAll conflicts resolved. Review with 'git status', then:")
    print("  git commit --no-edit")


if __name__ == "__main__":
    main()
