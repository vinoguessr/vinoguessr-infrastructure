# VinoGuessr — Shared Agent Rules

The source of truth for these rules is `vinoguessr/.github/AGENTS.md`. Every repository carries an effective copy of these rules plus its own verification commands. Do not assume a link alone makes the rules apply.

## Writing language

Write code, documentation, commit messages, labels, and PR titles in English. PRs are squash-merged with the PR title as the commit subject, so a PR title is a commit message. Write Issue bodies and PR bodies in Japanese. Issue Forms and the PR template stay in Japanese because they become the Issue and PR body.

## Purpose and architecture

VinoGuessr is a service for blind wine tasting: people create events, set questions, answer them, get scored, and build a season rating. The VinoGuessr API and PostgreSQL are the source of truth for business data such as users, events, questions, answers, and scores. External services are never the source of truth.

API: Swift 6 / Hummingbird / PostgreSQL / PostgresNIO / Valkey / Atlas / OpenAPI. Apple: SwiftUI, iOS, iPadOS, and macOS 27.0 or later. Web: Swift / Hummingbird. Infrastructure: Terraform / Google Cloud Run / Cloudflare (DNS, Images, Email) / Docker / OpenTelemetry. Target the latest stable OS and browser releases and do not add unnecessary backward-compatibility branches.

Sign-in uses passkeys (WebAuthn) and email one-time codes. Sessions use tokens issued by the API; never trust a user ID or event participation state sent by a client. Images are served through Cloudflare Images, and event tickets are Apple Wallet passes.

## Implementation flow and roles

1. Read the Issue, acceptance criteria, sub-issues, dependencies, existing PRs, and ADRs. Check for duplicates and blockers.
2. Make an implementation plan. While the Coding Agent implements, always run an independent Review Agent in parallel. Use a review from a separate context; the implementer re-reading its own work does not count.
3. When a change touches authentication (passkeys, email one-time codes, tokens), personal data, event participation authorization, scoring integrity, or Apple Wallet pass signing, also run a Security Review Agent in parallel. The Bug Triage Agent reproduces bugs and checks for duplicates; the Tool Review Agent checks permissions and execution safety of MCP servers, Skills, and CI.
4. Fix findings and actually run builds, tests, and any required runtime checks. Never pass a change on AI review alone. For bugs, search for duplicates, open an Issue if needed, and add a regression test.
5. After re-review, confirm GitHub Actions succeeded, and record the implementation, verification, review results, and open items in the PR. Never describe an unrun check as passing.

If parallel agents are unavailable, record that constraint and do not merge until the review conditions are met. A review does not automatically become a GitHub approval.

## Coding and testing

Respect the existing structure and keep changes small and scoped to one Issue. Enable Swift 6 concurrency checking and avoid unjustified `@unchecked Sendable` or swallowed errors. Define public APIs in OpenAPI first and never hand-edit generated code. Database changes come with a versioned, forward-only Atlas migration and integration tests.

For the API run `swift build` / `swift test` with integration tests against PostgreSQL and Valkey, and verify Atlas migrations. For the web run `swift build` / `swift test`. For Apple run build/test with the target Xcode and check required flows in the Simulator. For Terraform run `fmt` / `init -backend=false` / `validate`. A foundation PR without code runs structural checks only and must not be recorded as app-verified.

When changing the shared foundation in the `.github` repository, verify with `python scripts/validate_repository.py` (Python 3.11 or later, using `scripts/validation-requirements.txt`), `python -m unittest discover -s scripts -p 'test_*.py'`, and `actionlint`. Other repositories use the repository-specific section at the end of their AGENTS.md and the real verification steps in their README. Enable reusable workflows only after the calling repository actually has the code, lockfile, and tests.

## What each artifact explains

- **Code explains how**: express the implementation through structure, names, and logic.
- **Tests explain what**: state the expected behavior and the guaranteed result.
- **Commit messages explain why**: record why the change is needed and which problem it solves.
- **Code comments explain why not**: explain why alternatives were rejected and which constraints apply.

## Tracking workarounds

When you introduce an implementation or operation that temporarily works around a defect or constraint, check for related Issues and either add to an existing one or open a tracking Issue. Do not label a permanent design or a reasonable setting as a workaround without evidence.

A tracking Issue records why it was introduced, the impact, the affected code and PR, the permanent fix, the condition for removing it, upstream Issues/PRs if any, when to recheck, and the regression check. Leave a why-not comment with the constraint and the Issue reference at the relevant code, and reference the tracking Issue from the introducing PR.

The introducing PR references the tracking Issue without auto-close keywords. Close the tracking Issue only after the removal condition and the regression check confirm that the permanent fix landed or the workaround is no longer needed.

## Security

Never leave secrets, tokens, personal data, or real user data in code, logs, Issues, or PRs. Never print credential values. Verify that a passkey's challenge, origin, and RP ID match, and rate-limit one-time code and token issuance. The API verifies event participation and every write of answers and scores against a trusted session, and never finalizes a score from a client-supplied value. Never commit Apple Wallet pass signing keys or certificates (`.p12`, `.p8`, and similar).

Creating billed resources, production deploys, `terraform apply`, and broad IAM grants require explicit approval. Keep PII and credentials out of OpenTelemetry. Workflows use least-privilege permissions, and external actions are pinned to full commit SHAs. Shared reusable workflows are referenced by a SHA retained in the default branch history, never by an unmerged branch's SHA. Do not persist checkout credentials. Never run untrusted PR code with `pull_request_target`.

## MCP servers and Skills

At the start, check which MCP servers, Skills, and CLIs are actually available. Use the GitHub CLI, PostgreSQL and Atlas, Xcode MCP, the Simulator, SwiftUI Expert, Swift Build, Terraform, and gcloud as the task requires. Verify the official installation method and terms before installing anything locally. Do not expand system settings, authentication, or permissions without approval. Record unavailable tools along with the alternative command and what remains unverified. Distinguish installed from actually used.

## GitHub operations and documentation

Use `codex/` branches and PRs; never push directly to `main`. Never overwrite existing changes, repositories, or licenses. Do not send messages to other people beyond the required GitHub Issue and Project updates unless explicitly asked. Add Issues to the cross-repository Project and record acceptance criteria and real dependencies. Handle confidential vulnerabilities through SECURITY.md, not public Issues.

A PR records the related Issue, what changes, the checks run and their results, independent Review and Security Review results, and known limitations. Never fake required checks by skipping them. Releases have a tested commit and a changelog; Environments separate the approval boundaries of development, staging, and production. Use Packages only when there is something to distribute.

Record significant design changes as ADRs in `vinoguessr-docs` with context, decision, alternatives, and consequences, and update the wiki index. Update these rules and each repository's AGENTS.md as needed when bugs recur or a review finding matters. When the shared rules change, open follow-up PRs in the other repositories and state the source commit.

## Code review and merge conditions

1. Check the automatic Codex review on the PR. Verify the basis of each finding and make the required code fixes and regression tests.
2. Reply to each review thread with the fix, the commit, and the verification result. If no change is needed, explain why and do not hide open items.
3. After addressing findings, comment exactly `@codex review` on the PR to request a new review, and wait for the review of the latest commit.
4. Repeat for any new findings. Merge only after GitHub Codex reports no findings, no findings remain unaddressed, and the required CI has passed.
5. A missing review, a missing integration, or a failed run does not mean "no findings". Record the cause and the request URL, and keep the PR open. A passing independent local Review Agent does not replace this condition; the only exception is the usage-limit substitute below.

**Only when Codex cannot review because of its usage limit (insufficient tokens), a Claude Code independent review may substitute.** When substituting:

- After Codex reports its usage limit, run Claude Code's `reviewer` agent (`.claude/agents/reviewer.md`) as a separate run against the latest commit, in a context separate from the implementing agent. A review run during implementation never counts as the substitute. For changes to authentication, personal data, event participation authorization, scoring, or Apple Wallet pass signing, also run `security-reviewer`.
- Record in the PR the evidence that Codex was unavailable (the limit message and the URL of the request comment), the reviewed commit, and the findings and fixes.
- After fixing findings, review the latest commit again, and merge only once there are no findings and the required CI has passed.
- Reasons other than the usage limit (no response, missing integration, failed run) do not qualify for substitution. Investigate and record the cause, and keep the PR open.

This GitHub review is in addition to the independent Review Agent running in parallel during implementation and to real builds and tests. Requesting a review does not count as passing. Avoid automated replies and repeated identical requests, and record each review round and its commit in the PR.

## vinoguessr-infrastructure specifics

Shared rules source: `vinoguessr/.github@01fd9c61bce2139beb8ea173339d45c02d49b69f`.

Infrastructure code: Terraform / Google Cloud Run / Cloudflare / OpenTelemetry.

The VinoGuessr API and PostgreSQL are the source of truth for business data. Never expose credentials in Terraform state, plans, logs, or the repository. `vinoguessr-api`'s GitHub Actions builds container images and rolls them out to Cloud Run, and Terraform ignores drift in the running image.

After implementing, run `terraform fmt -check -recursive` / `terraform init -backend=false` / `terraform validate`. Do not run apply, production deploys, billed resource creation, or broad IAM grants without explicit approval.
