# vulcanic-anvil rfcs

Centralized RFC process and templates for cross-repository design changes.

When to open an RFC

- Use an RFC for changes that affect cross-repo contracts, public APIs, build/runtime characteristics, or developer workflows.

How to open an RFC

1. Fork and create a new directory using the `00000` placeholder (e.g. `rfcs/2026/00000-feature`).
2. Draft `RFC.md` using the template; include concise **Design Details** describing required files, workflow changes, and permissions.
3. Submit a PR — the placeholder `00000` will be replaced with the next available ID on merge.
4. After merge, implementation PRs in target repos must follow the branching convention and reference the approved RFC ID.

Quick rules

- Keep `Design Details` actionable and minimal; link to meeting notes if needed.
- Prefer the org reusable workflows and bootstrap templates to reduce per-repo drift.

Metadata header (required)

- `Creator`
- `Creation Date`
- `Status` (`draft`, `approved`, `implementing`, `implemented`, `superseded by NNNNN`)
- `PR` (GitHub PR URL that completed implementation; set after merge)
- `Target-Repos` (format: `repo-name [branch-url] [finish]`)
- `Supersedes`
