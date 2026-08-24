#!/usr/bin/env python3
"""
Resolves the test/food-impact-and-placement-log <- upstream/dev sync conflict (this round).

Run this from the Trio repo root, AFTER a merge of upstream/dev into
test/food-impact-and-placement-log (via GitHub Desktop's "Merge into current branch", or
`git merge upstream/dev`) has reported a conflict ONLY in Trio.xcodeproj/project.pbxproj.
If other files are also conflicted, stop and get a fresh look instead of running this.

This one is NOT a plain "keep both sides": upstream/dev's new hunk bundles two files
together -- GlassActionSheet.swift (genuinely new to this branch) and
ManualGlucoseEntryView.swift (which this branch already has registered elsewhere in the
file, under the identical GUID). Keeping both sides blindly would duplicate
ManualGlucoseEntryView.swift's PBXBuildFile/PBXFileReference entries under the same GUID,
which Xcode won't accept. So this keeps upstream's GlassActionSheet.swift lines only, and
drops its duplicate ManualGlucoseEntryView.swift lines (already present, unaffected,
elsewhere in the file).

Note: the only other files this merge touches (Config.xcconfig, the Core Data model
"contents" file, TreatmentsRootView.swift, and a handful of others) auto-merge cleanly on
their own -- nothing else needs manual attention.
"""
import re
import subprocess
import sys

PATH = "Trio.xcodeproj/project.pbxproj"


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

    block1_old = (
        "<<<<<<< HEAD\n=======\n"
        "\t\t7A11AC0DE000000000000171 /* GlassActionSheet.swift in Sources */ = "
        "{isa = PBXBuildFile; fileRef = 7A11AC0DE000000000000170 /* GlassActionSheet.swift */; };\n"
        "\t\t7A11AC0DE000000000000114 /* ManualGlucoseEntryView.swift in Sources */ = "
        "{isa = PBXBuildFile; fileRef = 7A11AC0DE000000000000014 /* ManualGlucoseEntryView.swift */; };\n"
        ">>>>>>> upstream/dev\n"
    )
    block1_new = (
        "\t\t7A11AC0DE000000000000171 /* GlassActionSheet.swift in Sources */ = "
        "{isa = PBXBuildFile; fileRef = 7A11AC0DE000000000000170 /* GlassActionSheet.swift */; };\n"
    )

    block2_old = (
        "<<<<<<< HEAD\n"
        "\t\t0998F4E23039C233005A2802 /* CapsuleSpinnerView.swift */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CapsuleSpinnerView.swift; sourceTree = \"<group>\"; };\n"
        "=======\n"
        "\t\t7A11AC0DE000000000000170 /* GlassActionSheet.swift */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassActionSheet.swift; sourceTree = \"<group>\"; };\n"
        "\t\t7A11AC0DE000000000000014 /* ManualGlucoseEntryView.swift */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ManualGlucoseEntryView.swift; sourceTree = \"<group>\"; };\n"
        ">>>>>>> upstream/dev\n"
    )
    block2_new = (
        "\t\t0998F4E23039C233005A2802 /* CapsuleSpinnerView.swift */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CapsuleSpinnerView.swift; sourceTree = \"<group>\"; };\n"
        "\t\t7A11AC0DE000000000000170 /* GlassActionSheet.swift */ = "
        "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassActionSheet.swift; sourceTree = \"<group>\"; };\n"
    )

    missing = [name for name, old in [("block1", block1_old), ("block2", block2_old)] if old not in content]
    if missing:
        print(f"Expected conflict block(s) not found as-is: {missing}")
        print("The conflict shape differs from what this script expects -- stopping, don't guess.")
        print("Get a fresh look instead of running this blindly.")
        sys.exit(1)

    content = content.replace(block1_old, block1_new, 1)
    content = content.replace(block2_old, block2_new, 1)

    still_conflicted = re.search(r"^(<{7}|={7}|>{7})", content, re.MULTILINE)
    if still_conflicted:
        print("Conflict markers still remain after resolving -- stopping.")
        sys.exit(1)

    with open(PATH, "w") as f:
        f.write(content)

    subprocess.run(["git", "add", PATH], check=True)
    print("Resolved both conflict blocks in Trio.xcodeproj/project.pbxproj.")
    print("\nReview with 'git status', then go back to GitHub Desktop -- it should now show")
    print("the merge as ready to commit. Commit it, then push as usual.")


if __name__ == "__main__":
    main()
