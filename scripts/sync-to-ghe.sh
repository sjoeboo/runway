#!/bin/bash
# Snapshot master to the internal GHE mirror with open-source artifacts stripped.
# Force-pushes a single commit to ghe/master — GHE history is replaced on each sync.
#
# Usage:
#   ./scripts/sync-to-ghe.sh              # strip, build, commit, force-push
#   ./scripts/sync-to-ghe.sh --dry-run    # strip, build, commit, stop before push
#                                         # (leaves the snapshot on the temp branch)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GHE_URL="git@ghe.spotify.net:mnicholson/runway.git"
GHE_REMOTE="ghe"
SOURCE_BRANCH="master"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "error: working tree has uncommitted tracked changes; commit or stash first" >&2
    git status --short
    exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$SOURCE_BRANCH" ]]; then
    echo "error: run from $SOURCE_BRANCH (currently on $CURRENT_BRANCH)" >&2
    exit 1
fi

if git remote get-url "$GHE_REMOTE" >/dev/null 2>&1; then
    EXISTING_URL="$(git remote get-url "$GHE_REMOTE")"
    if [[ "$EXISTING_URL" != "$GHE_URL" ]]; then
        echo "error: remote '$GHE_REMOTE' is $EXISTING_URL, expected $GHE_URL" >&2
        exit 1
    fi
else
    echo "==> Adding '$GHE_REMOTE' remote → $GHE_URL"
    git remote add "$GHE_REMOTE" "$GHE_URL"
fi

SOURCE_SHA="$(git rev-parse --short HEAD)"
TEMP_BRANCH="_ghe-sync-$(date +%s)"

echo "==> Creating temp branch $TEMP_BRANCH from $SOURCE_BRANCH@$SOURCE_SHA"
git switch -c "$TEMP_BRANCH"

cleanup() {
    if $DRY_RUN; then
        echo "==> Dry run: leaving $TEMP_BRANCH in place; snapshot commit is $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
        echo "    To inspect: git log -1 $TEMP_BRANCH"
        echo "    To discard: git switch $SOURCE_BRANCH && git branch -D $TEMP_BRANCH"
    else
        git switch "$SOURCE_BRANCH" >/dev/null 2>&1 || true
        git branch -D "$TEMP_BRANCH" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Running strip"
./scripts/strip-for-ghe.sh

# Self-delete sync tooling from the snapshot — they don't belong on GHE
rm -f scripts/strip-for-ghe.sh scripts/sync-to-ghe.sh

echo "==> Verifying build"
swift build

echo "==> Committing snapshot"
git add -A
git commit -m "Snapshot master@${SOURCE_SHA}

Automated sync from internal master with open-source artifacts
(.github/, CONTRIBUTING.md, README adaptations) stripped.
Snapshot only — GHE history is replaced on each sync."

if $DRY_RUN; then
    echo ""
    echo "==> Dry run complete. Snapshot sits on $TEMP_BRANCH."
    echo "    Re-run without --dry-run to force-push to $GHE_REMOTE/$SOURCE_BRANCH."
    exit 0
fi

echo "==> Force-pushing to $GHE_REMOTE/$SOURCE_BRANCH"
git push -f "$GHE_REMOTE" "HEAD:$SOURCE_BRANCH"

echo "==> Done. GHE is now at master@${SOURCE_SHA} (stripped)."
