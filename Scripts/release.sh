#!/bin/bash
# Pubblica una release: imposta la versione, compila (universale), crea Crocini.zip e la release
# su GitHub, che l'updater dell'app legge.
# Usage: Scripts/release.sh 1.2.0 "Release notes"
set -euo pipefail

VERSION="${1:?Usage: Scripts/release.sh <version> [notes]}"
NOTES="${2:-Crocini $VERSION}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit or stash your changes first: the release is tagged on the current commit." >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist

Scripts/build_app.sh
rm -f .build/Crocini.zip
ditto -c -k --keepParent .build/Crocini.app .build/Crocini.zip

ASSETS=(.build/Crocini.zip)

git add Resources/Info.plist
git commit -m "Release $VERSION" || true
git tag "v$VERSION"
git push
git push origin "v$VERSION"
gh release create "v$VERSION" "${ASSETS[@]}" --title "Crocini $VERSION" --notes "$NOTES"
echo "==> Released v$VERSION"
