# RFC-00000-establishing-governance

- **Creator**: lucatrepin
- **Creation Date**: 2026-05-25
- **Status**: draft
- **PR**: none
- **Target-Repos**: rfcs
- **Supersedes**: none

---

## Summary

This is the founding RFC for the **vulcanic-anvil** governance model. It defines how cross-repository decisions are proposed, reviewed, approved, implemented, and tracked through the RFC process.

It establishes the organizational workflow topology, the RFC repository structure, the metadata required for each RFC, and the automation used to keep implementation state synchronized across repositories.

## Motivation

The organization needs a governance system that is traceable, low-overhead, and practical to operate across multiple repositories.

This model was created to:

- make architectural decisions visible and reviewable before implementation;
- keep implementation status synchronized across repos;
- centralize automation instead of duplicating workflows in each repository;
- preserve a single source of truth for governance state;
- standardize how RFCs and implementation PRs are linked.

## Design Details

This section documents the governance contract that every RFC in this organization should follow.

### Canonical RFC structure

RFCs should be concise and use the same top-level shape so reviews stay predictable. The recommended sections are:

- `Summary`
- `Motivation`
- `Design Details`
- `Vantagens`
- `Disvantages`
- `Other Design`
- `Others`

This is a recommendation for consistency, not a rigid content template. The important rule is that every RFC remains easy to review, easy to implement, and easy to trace back to the decision that was made.

### Required header fields

Every RFC must keep the following header fields at the top of the file:

- `Creator` — who authored the RFC.
- `Creation Date` — when the RFC was created.
- `Status` — lifecycle state of the RFC.
- `PR` — the GitHub implementation PR URL, filled after merge.
- `Target-Repos` — the repositories that must implement the RFC.
- `Supersedes` — the RFC number replaced by this one, or `none`.

These fields are the source of truth for the governance model and must stay aligned with automation.

### Lifecycle

The RFC lifecycle is centralized and tracked in the RFC file itself:

1. A proposal starts as `draft` in a placeholder directory named `00000`.
2. After review, the approval automation renames the folder to the next sequential RFC ID and updates `Status` to `approved`.
3. When implementation starts in a target repository, the branch notification updates `Target-Repos` and moves the RFC to `implementing`.
4. When an implementation PR is merged, the merge notification records the PR URL in `PR` and marks the target repository as `[finish]`.
5. When every target repository is finished, the RFC moves to `implemented`.
6. If a later RFC replaces the current one, the older RFC is marked `superseded by NNNNN`.

### Repository roles

- The `.github` repository contains organization-level reusable workflows and bootstrap templates.
- The `rfcs` repository contains the RFC documents, the lifecycle orchestrator, and the canonical RFC process documentation.
- Target repositories only need thin wrapper workflows that call the org reusable workflows.

### Workflow topology

- Target repositories emit events through reusable workflows instead of implementing their own governance logic.
- Approval and implementation updates are sent to the `rfcs` repository through `repository_dispatch`.
- The reusable workflow layer keeps repository-specific configuration small and consistent.

### Automation model

- The RFC lifecycle is managed by a single Zig orchestrator in `rfcs/.github/scripts/rfc-manager.zig`.
- The orchestrator handles three actions:
  - `approve`: renames the placeholder RFC folder, assigns the next sequential ID, and marks the RFC as approved.
  - `branch`: records the implementation branch URL for a target repository and moves the RFC to `implementing` when work begins.
  - `merge`: marks a target repository as finished, records the implementation PR URL in `PR`, and marks the RFC as `implemented` once all targets are complete.
- The orchestrator uses the RFC file itself as the source of truth for status and implementation tracking.

### Events and payloads

- `branch_created` events include `rfc_id`, `repo_name`, and `branch_url`.
- `rfc_merged` events include `rfc_id`, `repo_name`, and `pr_url`.
- The `pr_url` is the GitHub PR HTML URL and is stored directly in the `PR` metadata field.

### Metadata model

- `Status` starts as `draft` and moves through the lifecycle as automation and review progress.
- `PR` is empty until implementation merge and then stores the implementation PR URL.
- `Target-Repos` lists the repositories that must finish implementation before the RFC is considered complete.

### Bootstrap and onboarding

- The bootstrap implementation in `.github/bootstrap/create-rfc-enabled-repo.zig` creates repositories with the notifier workflows already installed; `.sh` remains only as a thin convenience wrapper.
- The bootstrap flow can also register `ORG_GITHUB_TOKEN` as an organization secret for the target repository.
- This reduces per-repository drift and ensures new repos enter the governance model consistently.

### Permissions and secrets

- The reusable workflows use the organization secret `ORG_GITHUB_TOKEN` to call the RFC dispatch endpoint.
- The `rfcs` workflow requires `contents: write` so it can rename RFC folders and update metadata in the repository.
- The org secret should be granted only to the repositories that need to emit governance events.

### File layout and responsibilities

- `/.github/` (org repo): reusable workflows and bootstrap templates.
- `/rfcs/.github/scripts/`: the Zig orchestrator and any helper scripts.
- `/rfcs/rfcs/YYYY/NNNNN-name/RFC.md`: RFC documents with strict headers; `Target-Repos` lists only implementing repos.

## Vantagens

- Decisions are traceable across repositories.
- The organization keeps a single governance path instead of per-repo custom logic.
- Automation reduces drift and manual status tracking.
- Implementation PRs are linked directly to the RFC through the `PR` field.

## Disvantages

- The model adds a required documentation and review step before implementation.
- The automation depends on consistent repository naming, branch naming, and workflow usage.

## Other Design

- **Per-repository docs**: keep a governance note or README in every repo and track changes manually. This is simple, but it fragments the source of truth and makes lifecycle tracking harder.
- **Lightweight manual flow**: approve changes by labels, comments, or direct PR conversations without a dedicated RFC repository. This reduces ceremony, but it weakens traceability and makes it harder to link implementation PRs back to the original decision.
- **Per-repo automation**: install custom workflow logic in each repository instead of centralizing it. This gives local control, but it increases drift and maintenance cost.
- **Branch-only tracking**: rely only on branch naming and merge conventions without RFC metadata. This is minimal, but it loses explicit decision history and status reporting.

## Others

- The `rfcs` repository hosts the orchestrator and receives dispatch events.
- Target repositories emit events through the thin-wrapper workflows in the org `.github` repository.
- New repositories should be bootstrapped with the notifier workflows already installed.
- Keep the org secret `ORG_GITHUB_TOKEN` limited to the repositories that need to emit governance events.
- **Recommended**: use a single org secret named `ORG_GITHUB_TOKEN`, grant it only to repos that need to emit events, and rotate it centrally.
- **Alternatives**: per-repo secrets are supported but increase maintenance; use them only for small or temporary setups.
- Note: this RFC is the founder document for the governance model. Subsequent RFCs should extend or evolve this model rather than restating it.
