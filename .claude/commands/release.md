# Release Runway

Cut a new release for Runway. Accepts an optional version argument: `/release 0.3.0`
If no version is provided, auto-increment the minor version from the latest git tag.

## Steps

### 1. Determine version

- Run `git tag --sort=-creatordate | head -1` to find the latest tag
- If the user provided a version argument, use that (strip leading `v` if present)
- Otherwise, bump the minor version (e.g., v0.2.0 -> 0.3.0)
- Confirm the version with the user before proceeding

### 2. Gather changes

- Run `git log <last-tag>..HEAD --pretty=format:"%h %s"` to list commits since the last release
- Categorize each commit as **Added**, **Fixed**, or **Maintenance** based on the commit message:
  - `feat:` prefix or feature PRs -> Added
  - `fix:` prefix, bug fixes -> Fixed
  - Audits, dependency updates, docs -> Maintenance
- For each entry, include the PR number as a link: `([#NNN](https://github.com/sjoeboo/runway/pull/NNN))`
- Write concise, user-facing descriptions (not raw commit messages)

### 3. Update CHANGELOG.md

- Read the existing CHANGELOG.md
- Insert a new section at the top (below the header), following the existing Keep a Changelog format:
  ```
  ## [X.Y.Z] — YYYY-MM-DD

  ### Added
  - ...

  ### Fixed
  - ...

  ### Maintenance
  - ...

  [X.Y.Z]: https://github.com/sjoeboo/runway/compare/vPREV...vX.Y.Z
  ```
- Use today's date
- Only include categories that have entries

### 4. Update README.md

- Review the new features and check if the README is missing any of them
- Update the relevant sections (Session Management, Terminal, Keyboard Shortcuts, etc.)
- Update the test count: run `swift test 2>&1 | tail -1` and extract the count
- Update the keyboard shortcut count in the Highlights table if shortcuts were added
- Only make changes if something is actually missing — don't rewrite sections unnecessarily

### 5. Update CLAUDE.md

- If the test count changed, update it in CLAUDE.md too

### 6. Commit

- Stage CHANGELOG.md, README.md, and CLAUDE.md (only if changed)
- Commit with message: `Release vX.Y.Z: <brief summary of top features>`

### 7. Tag

- Create an annotated tag: `git tag -a vX.Y.Z -m "<release notes summary>"`
- The tag message should include a brief list of Added/Fixed/Maintenance items

### 8. Push

- Push the commit and tag: `git push origin master vX.Y.Z`
- Confirm success and report the tag URL: `https://github.com/sjoeboo/runway/releases/tag/vX.Y.Z`

## Notes

- Follow the existing CHANGELOG.md style exactly (Keep a Changelog format)
- PR links use the `sjoeboo/runway` repo path
- Tags are always prefixed with `v` (e.g., `v0.2.0`)
- CHANGELOG versions omit the `v` prefix (e.g., `[0.2.0]`)
