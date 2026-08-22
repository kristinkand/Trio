#!/usr/bin/env python3
"""
Resolves the project.pbxproj conflict from cherry-picking upstream's revert
commit (0f356e490, "Revert 'upgrade looping animation and remove looping
text'") onto a branch that has its own later additions in the same file.

The revert deletes the CapsuleSpinnerView.swift PBXBuildFile entry; our side
also has later, unrelated additions sitting next to it. This keeps every
line from our side EXCEPT the CapsuleSpinnerView.swift one (which the
revert is removing), and drops the conflict markers.

Run this from the Trio repo root after:
  git cherry-pick 0f356e490
has reported a conflict ONLY in Trio.xcodeproj/project.pbxproj. If other
files are also conflicted, stop and get a fresh look instead of running this.
"""
import re
import subprocess
import sys

PATH = "Trio.xcodeproj/project.pbxproj"

CONFLICT_RE = re.compile(
    r"<<<<<<< HEAD\n(.*?)\n?=======\n(.*?)>>>>>>> [^\n]+\n", re.DOTALL
)


def main():
    status = subprocess.run(
        ["git", "status", "--short"], capture_output=True, text=True, check=True
    ).stdout
    unmerged = [line[3:] for line in status.splitlines() if line.startswith("UU ")]

    unexpected = [f for f in unmerged if f != PATH]
    if unexpected:
        print("Found unexpected conflicts beyond project.pbxproj:")
        for f in unexpected:
            print(f"  {f}")
        print("Stopping -- this needs a fresh look, don't resolve blindly.")
        sys.exit(1)

    if not unmerged:
        print(f"No conflict in {PATH}. Nothing to do.")
        sys.exit(0)

    with open(PATH) as f:
        content = f.read()

    def resolve(m):
        ours = m.group(1)
        kept = [line for line in ours.split("\n") if "CapsuleSpinnerView" not in line]
        result = "\n".join(kept)
        return result + "\n" if result else ""

    resolved, n = CONFLICT_RE.subn(resolve, content)

    if n == 0:
        print("No recognizable conflict blocks found -- stopping, don't guess.")
        sys.exit(1)

    print(f"Resolved {n} conflict block(s) in {PATH} (removed CapsuleSpinnerView entry, kept the rest).")

    with open(PATH, "w") as f:
        f.write(resolved)

    still_conflicted = re.search(r"^(<{7}|={7}|>{7})", resolved, re.MULTILINE)
    if still_conflicted:
        print("Conflict markers still remain after resolving -- stopping.")
        sys.exit(1)

    if "CapsuleSpinnerView" in resolved:
        print("Warning: CapsuleSpinnerView still referenced elsewhere in the file -- check manually.")
        sys.exit(1)

    subprocess.run(["git", "add", PATH], check=True)
    print("\nAll conflicts resolved. Review with 'git status', then:")
    print("  git cherry-pick --continue --no-edit")


if __name__ == "__main__":
    main()
