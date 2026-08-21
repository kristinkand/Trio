#!/usr/bin/env python3
"""
Resolves this round's upstream/dev sync conflicts:

1. Trio.xcodeproj/project.pbxproj -- both sides independently added a new
   PBXBuildFile/PBXFileReference entry at the same insertion point. Keeps
   BOTH sides' lines (ours first, then theirs).

2. Trio/Sources/Localizations/Main/Localizable.xcstrings -- both sides added
   a new "comment" usage-note to the same shared localized string ("Got
   it!"). Merges the two comments (each a \\n-separated list of usages) into
   one combined, de-duplicated comment. This only touches the internal
   developer-facing comment metadata, not the actual translated text.

Run this from the Trio repo root, after `git merge upstream/dev` has
reported conflicts ONLY in these two files. If other files are also
conflicted, stop and get a fresh look instead of running this.
"""
import json
import re
import subprocess
import sys

PBXPROJ = "Trio.xcodeproj/project.pbxproj"
XCSTRINGS = "Trio/Sources/Localizations/Main/Localizable.xcstrings"
EXPECTED = {PBXPROJ, XCSTRINGS}

CONFLICT_RE = re.compile(
    r"<<<<<<< HEAD\n(.*?)\n=======\n(.*?)\n>>>>>>> upstream/dev\n", re.DOTALL
)


def resolve_pbxproj(path):
    with open(path) as f:
        content = f.read()

    def keep_both(m):
        return m.group(1) + "\n" + m.group(2) + "\n"

    resolved, n = CONFLICT_RE.subn(keep_both, content)
    if n == 0:
        return False
    with open(path, "w") as f:
        f.write(resolved)
    print(f"{path}: resolved {n} block(s) (kept both sides' entries)")
    return True


def resolve_xcstrings(path):
    with open(path) as f:
        content = f.read()

    def merge_comment(m):
        ours_line, theirs_line = m.group(1), m.group(2)
        ours_match = re.search(r'"comment"\s*:\s*"(.*)",?\s*$', ours_line)
        theirs_match = re.search(r'"comment"\s*:\s*"(.*)",?\s*$', theirs_line)
        if not ours_match or not theirs_match:
            # Not a plain "comment" field conflict -- don't guess, bail loudly.
            raise ValueError(
                "Unrecognized xcstrings conflict shape (not a simple 'comment' "
                "field) -- stopping rather than resolving blindly:\n"
                f"  ours:   {ours_line!r}\n  theirs: {theirs_line!r}"
            )
        ours_parts = ours_match.group(1).split("\\n")
        theirs_parts = theirs_match.group(1).split("\\n")
        merged = list(dict.fromkeys(ours_parts + theirs_parts))
        merged_val = "\\n".join(merged)
        prefix = re.match(r'^(\s*"comment"\s*:\s*")', ours_line).group(1)
        return f'{prefix}{merged_val}",\n'

    resolved, n = CONFLICT_RE.subn(merge_comment, content)
    if n == 0:
        return False

    # Validate the result is still well-formed JSON before writing it out.
    json.loads(resolved)

    with open(path, "w") as f:
        f.write(resolved)
    print(f"{path}: resolved {n} block(s) (merged comment text)")
    return True


def main():
    status = subprocess.run(
        ["git", "status", "--short"], capture_output=True, text=True, check=True
    ).stdout
    unmerged = {line[3:] for line in status.splitlines() if line.startswith("UU ")}

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

    resolved_any = []
    try:
        if PBXPROJ in unmerged:
            if resolve_pbxproj(PBXPROJ):
                resolved_any.append(PBXPROJ)
        if XCSTRINGS in unmerged:
            if resolve_xcstrings(XCSTRINGS):
                resolved_any.append(XCSTRINGS)
    except ValueError as e:
        print(str(e))
        sys.exit(1)

    for f in resolved_any:
        # Double check nothing was missed before staging.
        with open(f) as fh:
            if re.search(r"^(<{7}|={7}|>{7})", fh.read(), re.MULTILINE):
                print(f"{f}: conflict markers still remain after resolving -- stopping.")
                sys.exit(1)
        subprocess.run(["git", "add", f], check=True)

    print("\nAll conflicts resolved. Review with 'git status', then:")
    print("  git commit --no-edit")


if __name__ == "__main__":
    main()
