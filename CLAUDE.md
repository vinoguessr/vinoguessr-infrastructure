@AGENTS.md

## Claude Code

This file only makes Claude Code load AGENTS.md. AGENTS.md is the source of truth for the rules; do not duplicate them here.

`.claude/agents/reviewer.md` and `.claude/agents/security-reviewer.md` are read-only review agents. Run them in a context separate from the implementing agent, either as the parallel Review / Security Review Agent during implementation, or as the substitute for GitHub Codex review when Codex cannot review because of its usage limit (insufficient tokens).

A substitute review is a separate run against the latest commit after Codex reported the limit; a review run during implementation never counts as the substitute. Record in the PR the evidence that Codex was unavailable, the reviewed commit, and the findings and fixes.
