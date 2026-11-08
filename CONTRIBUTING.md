# Contributing

Read [AGENTS.md](AGENTS.md) first. Check the Issue and its dependencies, and implement on a `codex/<topic>` branch. Never push directly to `main`.

- Search for duplicate Issues and record acceptance criteria, dependencies, and the target repository.
- Run an independent Review Agent in parallel while implementing. Also run a Security Review Agent for authentication, personal data, event participation authorization, scoring, and Apple Wallet pass signing.
- Record working builds, tests, and GitHub Actions results in the PR. Also state any MCP servers that were not run or not available.
- Bug fixes include a reproduction and a regression test, and are re-reviewed after fixing findings.
- PRs are reviewed by GitHub Codex. Only when Codex cannot review because of its usage limit, substitute a Claude Code review and record the evidence in the PR.
- Record design decisions in ADRs, the index in the wiki, and recurring lessons in AGENTS.md.
- Write code, documentation, commit messages, labels, and PR titles in English, and Issue and PR bodies in Japanese.

Updates to reusable workflows are not applied to every caller automatically. Pin calls to a commit SHA, and open follow-up PRs after verification.

In this repository, run the commands in the README and `actionlint`. If an Issue Form uses labels, create them in the target repository first. CODEOWNERS, AGENTS.md, CLAUDE.md, and workflows are not inherited from the organization's shared settings.
