#!/bin/bash
# Strip open-source artifacts from the working tree for internal GHE distribution.
# Mirrors the surgical adaptations already landed on ghe.spotify.net/mnicholson/runway:
#   - delete .github/ (CI, issue templates, dependabot)
#   - delete CONTRIBUTING.md (external-contributor guide)
#   - rewrite README.md (badges, Releases section, clone URL, CI heading, License)
#
# Sparkle, UpdaterController, Info.plist SU* keys, and .claude/commands/release.md
# are intentionally left in place — Sparkle works for internal builds against a
# self-hosted appcast, so there's no reason to rip it out.
#
# Idempotent: safe to run on an already-stripped tree.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

test -f Package.swift || { echo "error: not a runway checkout" >&2; exit 1; }
grep -q 'name: "Runway"' Package.swift || { echo "error: not a runway checkout" >&2; exit 1; }

echo "==> Deleting open-source-only files"
rm -rf .github/
rm -f CONTRIBUTING.md

echo "==> Adapting README.md for internal distribution"

# 1. Remove the shields.io badge block (matched by its unique img.shields.io content
#    so we don't accidentally catch the Hero.png <p align="center"> above it)
perl -i -0pe 's|<p align="center">\n(  <img src="https://img\.shields\.io[^\n]*>\n)+</p>\n\n||' README.md

# 2. Remove the "Download (recommended)" section up to (but not including) "### Build from source"
perl -i -0pe 's|### Download \(recommended\).*?(?=### Build from source)||s' README.md

# 3. Rewrite the clone URL
sed -i '' 's|https://github\.com/sjoeboo/runway\.git|git@ghe.spotify.net:mnicholson/runway.git|' README.md

# 4. Drop the Sparkle row from the dependency table
sed -i '' '/^| \[Sparkle\](/d' README.md

# 5. Rename CI & Testing → Testing
sed -i '' 's|^## CI & Testing$|## Testing|' README.md

# 6. Drop two GitHub-specific CI bullets
sed -i '' \
    -e '/^- \*\*GitHub Actions CI\*\* on every PR:/d' \
    -e '/^- \*\*Branch protection\*\* on `master`/d' \
    README.md

# 7. Insert "make check" bullet + trailing blank line after the Pre-commit bullet
#    (the extra blank matches the double-blank before "## Planned" on GHE's master)
perl -i -pe 's|^(- \*\*Pre-commit hooks\*\* run lint \+ format checks locally)$|$1\n- Run `make check` to build, test, lint, and format-check\n|' README.md

# 8. Drop the License section at file tail
sed -i '' '/^## License$/,$d' README.md

echo "==> Strip complete."
