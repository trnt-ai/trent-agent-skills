<!--
CUSTOMER-FACING TERMINOLOGY ONLY.

Do not add to this file:
- Internal service names, codenames, or pre-release product names
- AWS account IDs, VPC IDs, ARNs, or other infrastructure identifiers
- Internal URLs, hostnames, or repo names not already public
- Engineering team names or org-chart references

If unsure whether a term is public, check the live trent-ai GitBook
(https://trent-ai.gitbook.io) before adding it here.
-->

# Canonical Terminology

The canonical names that must appear in generated customer documentation.
Edit this file when a product is renamed, a UI element is added, or a
severity / lifecycle vocabulary changes.

---

## Brand

| Canonical | Use as | Notes |
|-----------|--------|-------|
| Trent | Brand name | Always capitalized. Bold on first mention in a section: **Trent** |
| Trent AI | Full company name | Use only in introductions or formal context |
| trent.ai | Marketing site | Lowercase. Link: https://trent.ai |
| app.trent.ai | Product app | Lowercase. Link: https://app.trent.ai |

---

## Products

The product naming has shifted. Use the **Canonical** column. The **Deprecated** column lists older names that still appear in some pages and source PRs — translate these to canonical names in new docs.

| Canonical | Deprecated (translate) | Surface | One-line description |
|-----------|------------------------|---------|----------------------|
| **Security Assessment** | Threat Assessor, Threat Assessment | Web app workflow | End-to-end security workflow for agents, applications, code, websites, and ideas |
| **Security Advisor** | AppSec Advisor | Chat interface and MCP skill | 24/7 application security expert that guides design and remediation |
| **Prompt Guard** | — | API + SDK | Real-time safety guardrails for generative AI applications |

When a deprecated name appears in a source PR title or commit message, replace it with the canonical name in the generated doc. The validation step in `doc-publisher` flags any remaining deprecated names — advisory, not blocking. Historical references in changelogs are legitimate.

---

## Agent Roles (Agentic AI Security Solutions)

Used in `products/agentic-ai-security-solutions.md` and integration pages.

| Term | Bold? | Notes |
|------|-------|-------|
| **Scan** / **Threat Scanning Agent** | Yes | The continuous-observation agent |
| **Judge** / **Analysis Agent** | Yes | The signal-versus-noise agent |
| **Mitigate** / **Remediation Agent** | Yes | The patch-and-validate agent |
| **Evaluate** / **Security Posture Agent** | Yes | The trends-and-forecasting agent |

---

## UI Elements

Always **bold** when referenced in instructions. These names match the live product UI.

### Top-level navigation
- **Projects**
- **AppSec Advisor** (left sidebar entry — the chat surface, not the product)
- **Context Hub**
- **Profile → Connections**
- **Account Icon → Connections**

### Project workflow
- **New Project**
- **Run Full Analysis**
- **Goals Review**
- **Re-run** / **Re-Run Analysis**

### Project dashboard tabs
- **Home**
- **Vulnerabilities**
- **Tasks**
- **System View**
- **DFD Tab**
- **Reports** / **Reports Tab**
- **Secure It!**
- **Plan**
- **Focus Mode**
- **Design Doc**

### Action buttons within Focus Mode
- **What You Need to Do**
- **View Impact**
- **How to Fix It**
- **New Chat**

### Setup-flow buttons
- **Connect GitHub Repository**
- **Describe Your Idea**
- **Create Threat Assessment** (note: still uses old name in product UI)
- **Set Up Custom MCP**
- **Generate API Key**
- **Add MCP server** / **Add server**

---

## Severity

Always capitalized, always bold when listed.

| Term | Use |
|------|-----|
| **Critical** | Highest severity. Always remediate first |
| **High** | Remediate before launch |
| **Medium** | Plan remediation |
| **Low** | Track and address opportunistically |

When listing severities in prose, order as: **Critical**, **High**, **Medium**, **Low**.
When showing counts: `CRITICAL (2):`, `HIGH (3):` — uppercase, in code blocks only.

---

## Project Lifecycle

Project state names. Always **bold**, always title case.

- **Pending** — project created, analysis not started yet
- **Goals Ready** — review and edit goals before the full scan
- **Running** — six-phase analysis in progress
- **Completed** — full dashboard, findings, and reports available
- **Failed** — analysis needs attention or retry

When listing lifecycle in prose, follow this order.

---

## Analysis Phases

The six phases of a full scan. Numbered, bold, in this order:

1. **Initializing**
2. **Analyzing Code**
3. **Analyzing Docs**
4. **Identifying Threats**
5. **Generating Remediation**
6. **Finalizing**

---

## Security Frameworks

| Term | Use | Notes |
|------|-----|-------|
| STRIDE | Reference | Spell out categories on first mention: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege |
| SOC2 | Reference | Uppercase, no space |
| HIPAA | Reference | Uppercase |
| PCI-DSS | Reference | Hyphenated, uppercase |
| GDPR | Reference | Uppercase |
| ISO 27001 | Reference | Space between ISO and number |

### STRIDE categories (always title-bold when listed)
- **Spoofing**
- **Tampering**
- **Repudiation**
- **Information Disclosure**
- **Denial of Service**
- **Elevation of Privilege**

---

## Integrations

Canonical names of supported integration targets. Each has a doc at `integrations/{slug}-integration.md`.

| Canonical | Slug | Notes |
|-----------|------|-------|
| **Bolt.new** | `bolt.new` | Period in the name, not a typo |
| **Claude Code** | `claude-code` | Two words |
| **Lovable** | `lovable` | One word |
| **OpenClaw** | `openclaw` | Camel case, no space |

---

## Common Phrases (use exactly)

These phrases recur across pages. Use them verbatim — readers expect them.

| Context | Phrase |
|---------|--------|
| Prerequisites lead-in | "Before you begin, you'll need:" |
| Help section heading | `### Need Help?` |
| Help link target | `[Help Centre](../support/help-centre.md)` (British spelling, intentional) |
| Tip format | `✅ **Title** — explanation` |
| Severity prioritization | "Start with **Critical** and **High** findings first." |
| GitHub private-repo callout | "For private GitHub repos, connect GitHub first in **Profile → Connections**." |
| Tag-line summary | "You build with X. You secure with Trent." |
| Detection-versus-guidance | "This is not just detection. It is ongoing guidance." |

---

## Spelling Conventions

- **Help Centre** — British spelling. Always.
- **customer-facing** — hyphenated.
- **agentic** — lowercase.
- **multi-tenant**, **multi-step**, **multi-cloud** — hyphenated.
- **re-run**, **re-scan** — hyphenated.
- **API key** — two words, lowercase except API.
- **GitHub**, **PostgreSQL**, **JavaScript**, **Node.js** — match the project's own capitalization.
