#!/usr/bin/env python3
import re
import subprocess
import sys

PATH = "Trio.xcodeproj/project.pbxproj"


def main():
    unmerged = subprocess.run(
        ["git", "status", "--short"], capture_output=True, text=True, check=True
    ).stdout
    unmerged_files = [
        line[3:] for line in unmerged.splitlines() if line.startswith("UU ")
    ]

    unexpected = [f for f in unmerged_files if f != PATH]
    if unexpected:
        print("Found unexpected conflicts beyond project.pbxproj:")
        for f in unexpected:
            print(f"  {f}")
        print("Stopping -- this needs a fresh look, don't resolve blindly.")
        sys.exit(1)

    if not unmerged_files:
        print(f"No conflict in {PATH}. Nothing to do.")
        sys.exit(0)

    with open(PATH) as f:
        content = f.read()

    pattern = re.compile(
        r"<<<<<<< HEAD\n(.*?)\n=======\n(.*?)\n>>>>>>> upstream/dev\n", re.DOTALL
    )

    def resolve(m):
        ours, theirs = m.group(1), m.group(2)
        return ours + "\n" + theirs + "\n"

    resolved, n = pattern.subn(resolve, content)

    if n == 0:
        print("No recognizable conflict blocks found -- stopping, don't guess.")
        sys.exit(1)

    print(f"Resolved {n} conflict block(s) in {PATH} (kept both sides' entries).")

    with open(PATH, "w") as f:
        f.write(resolved)

    still_conflicted = re.search(r"^(<{7}|={7}|>{7})", resolved, re.MULTILINE)
    if still_conflicted:
        print("Conflict markers still remain after resolving -- stopping.")
        sys.exit(1)

    subprocess.run(["git", "add", PATH], check=True)
    print("\nAll conflicts resolved. Review with 'git status', then:")
    print("  git commit --no-edit")


if __name__ == "__main__":
    main()
