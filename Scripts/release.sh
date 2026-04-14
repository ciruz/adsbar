#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$REPO_ROOT/ADSBar/ADSBar.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: project.pbxproj not found at $PBXPROJ"
    exit 1
fi

CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //' | sed 's/;.*//' | tr -d '[:space:]')
echo "Current version: $CURRENT_VERSION"

read -rp "New version (e.g. 1.1): " NEW_VERSION
if [ -z "$NEW_VERSION" ]; then
    echo "No version provided, aborting."
    exit 1
fi

if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "Error: version must be in X.Y or X.Y.Z format"
    exit 1
fi

sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"

CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= //' | sed 's/;.*//' | tr -d '[:space:]')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

echo "Updated: $CURRENT_VERSION -> $NEW_VERSION (build $CURRENT_BUILD -> $NEW_BUILD)"

git add "$PBXPROJ"
git commit -m "Bump version to $NEW_VERSION ($NEW_BUILD)"

git tag -a "v$NEW_VERSION" -m "Release $NEW_VERSION"
echo "Created tag v$NEW_VERSION"

echo ""
echo "--- Next steps ---"
echo "1. Push the tag:  git push origin main --tags"
echo "2. GitHub Actions will build, sign, notarize, and create the release"
