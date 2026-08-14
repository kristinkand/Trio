#!/bin/bash
EVERSENSE_COMMIT="ec1fa60bfabec8784b235ae65a1ea4df949d8580"
OMNIPOD_COMMIT="792dc1974c3cb3138350883dbab32be48d2cd2ba"

if [ ! -f "Trio.xcodeproj/project.pbxproj" ]; then
    echo "Run this from the Trio repo root."
    exit 1
fi

UNMERGED=$(git status --short | grep -E "^UU" | awk '{print $2}')
UNEXPECTED=$(echo "$UNMERGED" | grep -v -E "^(EversenseKit|OmnipodKit)$" || true)

if [ -n "$UNEXPECTED" ]; then
    echo "Found unexpected conflicts beyond EversenseKit/OmnipodKit:"
    echo "$UNEXPECTED"
    echo "Stopping -- this needs a fresh look, don't resolve blindly."
    exit 1
fi

if [ -z "$UNMERGED" ]; then
    echo "No EversenseKit/OmnipodKit conflicts found. Nothing to do."
    exit 0
fi

echo "Resolving submodule pointers to upstream's (newer) commits..."
git submodule update --init -- EversenseKit OmnipodKit

if echo "$UNMERGED" | grep -q "EversenseKit"; then
    (cd EversenseKit && git fetch origin "$EVERSENSE_COMMIT" && git checkout -q "$EVERSENSE_COMMIT")
    git add EversenseKit
    echo "  EversenseKit -> $EVERSENSE_COMMIT"
fi

if echo "$UNMERGED" | grep -q "OmnipodKit"; then
    (cd OmnipodKit && git fetch origin "$OMNIPOD_COMMIT" && git checkout -q "$OMNIPOD_COMMIT")
    git add OmnipodKit
    echo "  OmnipodKit -> $OMNIPOD_COMMIT"
fi

STILL_UNMERGED=$(git status --short | grep -E "^UU" || true)
if [ -n "$STILL_UNMERGED" ]; then
    echo "Still unmerged after resolving:"
    echo "$STILL_UNMERGED"
    exit 1
fi

echo ""
echo "All conflicts resolved. Review with 'git status', then:"
echo "  git commit --no-edit"
