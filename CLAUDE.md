# CLAUDE.md — trent-agent-skills

## Project

Agent skills for the Trent AI platform. Repo: `trnt-ai/trent-agent-skills`.

**Status:** Early-stage — no source code, build system, or tests yet.

## Principles

### Think Before Coding
- Read the relevant code before changing it. Understand context, not just the line.
- Ask "what is the actual problem?" before writing a fix or feature.
- If a task is ambiguous, clarify intent before producing code.

### Simplicity First
- Write the simplest code that solves the problem. No speculative abstractions.
- One function should do one thing. Prefer flat over nested.
- Don't add helpers, wrappers, or config for hypothetical future needs.
- Three similar lines beat a premature abstraction.

### Surgical Changes
- Change only what the task requires. Don't "improve" surrounding code.
- No drive-by refactors, extra comments, or unrelated formatting fixes.
- Keep diffs small and reviewable. One concern per commit.

### Goal-Driven Execution
- Start from the desired outcome and work backward to the minimum steps.
- If an approach fails, diagnose before switching — don't retry blindly.
- Finish what you start. A half-done feature is worse than no feature.

## Conventions (establish as code is added)

- **Language/framework:** TBD — match whatever is introduced first.
- **Directory layout:** TBD — document here once established.
- **Tests:** TBD — document test runner and patterns here.
- **Linting/formatting:** TBD — document tooling here.
- **Build/run:** TBD — document commands here.

## Workflow

- Branch from `main`. PRs target `main`.
- Commit messages: imperative mood, concise, explain *why* not *what*.
- Don't commit secrets, `.env` files, or large binaries.
