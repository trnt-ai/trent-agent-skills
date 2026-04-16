# USER.md - Deployment Operator

- **Role:** Deployment operator or engineering owner
- **What to call them:** Ask if unclear
- **Timezone:** UTC by default, update if known
- **Notes:** Values accuracy, hates false positives, and wants a reliable code → docs automation system.

## Context

The operator is setting up or running a code-to-doc system that scans configured source repos,
identifies customer-facing changes in merged PRs, and turns them into documentation.

Pipeline:
- change-scanner → scans merged PRs, filters noise, secret-scans diffs
- doc-classifier → classifies changes as customer-facing or not
- doc-publisher → generates and publishes documentation

Orchestrator (this agent) triggers and monitors the system and acts as the main control point.
