#!/usr/bin/env python3
"""Git merge driver for Localizable.xcstrings.

Does a proper key-level JSON 3-way merge instead of git's default
line-based text merge. The default merge treats this file as lines of
text, and since it's a huge, alphabetically-sorted, auto-generated
catalog, two completely unrelated string keys often land on adjacent
lines -- git then reports a "conflict" that isn't really one; the two
sides just touched different, unrelated dictionary keys.

Once registered (see setup below), git invokes this automatically on
every merge, pull, or cherry-pick that touches this file. No manual
steps needed for the common case.

Git merge driver contract: called as `<driver> %O %A %B`, where %O is
the ancestor (base) version, %A is our version (this script must
overwrite %A in place with the result), and %B is their version.
Exit 0 = merged cleanly. Exit 1 = a real conflict (two sides changed
the very same key to different values) -- %A is left as our side, and
this needs a person to resolve it by hand, same as any other conflict.
"""
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def merge_dict(anc, a, b, warnings):
    """3-way merge of a flat dict of JSON values, preferring whichever side
    actually changed a given key relative to the ancestor. Only warns (and
    falls back to "ours") when both sides changed the SAME key to
    DIFFERENT values -- a real conflict, not just adjacent-key noise."""
    result = dict(a)
    for k in set(a.keys()) | set(b.keys()):
        anc_v = anc.get(k)
        a_v = a.get(k)
        b_v = b.get(k)
        if k not in a and k in b:
            if b_v != anc_v:
                result[k] = b_v
            continue
        if k not in b and k in a:
            continue  # kept ours already; theirs deleted it
        if a_v == b_v:
            result[k] = a_v
            continue
        a_changed = a_v != anc_v
        b_changed = b_v != anc_v
        if a_changed and not b_changed:
            result[k] = a_v
        elif b_changed and not a_changed:
            result[k] = b_v
        else:
            warnings.append(k)
    return result


def main():
    if len(sys.argv) != 4:
        print("usage: merge-xcstrings-json.py %O %A %B", file=sys.stderr)
        sys.exit(2)

    ancestor_path, ours_path, theirs_path = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        ancestor = load(ancestor_path)
        ours = load(ours_path)
        theirs = load(theirs_path)
    except Exception as e:
        print(f"xcstrings merge driver: couldn't parse as JSON ({e}); falling back to a normal conflict", file=sys.stderr)
        sys.exit(1)

    warnings = []
    merged = dict(ours)
    merged["strings"] = merge_dict(ancestor.get("strings", {}), ours.get("strings", {}), theirs.get("strings", {}), warnings)

    for top_key in ("sourceLanguage", "version"):
        if ours.get(top_key) != theirs.get(top_key) and ours.get(top_key) == ancestor.get(top_key):
            merged[top_key] = theirs.get(top_key)
        elif ours.get(top_key) != theirs.get(top_key) and theirs.get(top_key) != ancestor.get(top_key):
            warnings.append(f"(top-level) {top_key}")

    if warnings:
        print(
            f"xcstrings merge driver: {len(warnings)} key(s) changed differently on both sides, needs a person: "
            + ", ".join(warnings[:20]) + (" ..." if len(warnings) > 20 else ""),
            file=sys.stderr,
        )
        sys.exit(1)

    with open(ours_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(merged, indent=2, ensure_ascii=False, sort_keys=True) + "\n")

    print(f"xcstrings merge driver: merged cleanly ({len(merged['strings'])} strings)", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
