---
name: doc-style
description: Tone, structure, and messaging framework for trnt-ai customer documentation
version: 1.1.0
user-invocable: false
---

# trnt-ai Documentation Style Guide

Apply these rules whenever generating or updating customer documentation.
This file pins voice and structure to match the live trent-ai GitBook docs.

This skill has three layers. Read all three before generating content.

| File | What it pins | When to edit |
|------|--------------|--------------|
| `SKILL.md` (this file) | Voice, formatting, what to avoid | Rarely — voice is stable |
| `terminology.md` | Canonical product, UI, severity, lifecycle names | When a product is renamed or added |
| `section-patterns.md` | Page anatomy and reusable section templates | When a new doc type is added |

Apply the layers in order: voice (this file) → vocabulary (`terminology.md`) → structure (`section-patterns.md`).

---

## Voice & Tone

**Audience:** Security engineers and developers building applications.
Not: executives, non-technical users, or beginners.

**Voice:**
- Direct and confident — state what things do, not what they "may" or "might" do
- Professional but not formal — clear sentences, no corporate speak
- Helpful — lead with what the reader needs to do, not background context
- Concise — every sentence earns its place
- Imperative for steps ("Click", "Run", "Open") — never "you should click"
- Second person ("you can", "you'll need") — never "the user"

**Avoid:**
- Filler openers ("This guide will help you...", "In this section...")
- Passive voice ("The assessment is run" → "Trent runs the assessment")
- Hedging ("may", "might", "could", "potentially")
- Jargon not defined on first use
- Internal codenames, file paths, or implementation details
- Marketing language ("powerful", "seamless", "revolutionary", "cutting-edge")
- Em-dash decoration in body prose; em-dashes are reserved for `✅ **Tip name** —` lines and short title-glosses

---

## Formatting Conventions

### Section separators
Use `***` (three asterisks on their own line) between major `##` sections.
Skip the separator before the first section and after the last.

### Bolding rules
Bold these always:
- UI element names: **Projects**, **New Project**, **Focus Mode**, **Plan**, **Secure It!**, **Run Full Analysis**
- Severity levels: **Critical**, **High**, **Medium**, **Low**
- Lifecycle states: **Pending**, **Goals Ready**, **Running**, **Completed**, **Failed**
- Brand and product names on first mention in a section (see `terminology.md`)
- Tip titles in `✅ **Title** — explanation` lines

Do not bold for emphasis in body prose. Use plain text.

### Heading levels
- `#` — Page title only (one per page)
- `##` — Major sections
- `###` — Subsections / numbered steps (`### 1. Verb-first`)
- Never go deeper than `###`

### Frontmatter
Pages with a meaningful one-line summary use YAML frontmatter:
```yaml
---
description: >-
  One-sentence summary that GitBook surfaces in search and navigation.
---
```
Otherwise, a one-sentence subtitle directly under the `# Title` is enough.

### Callouts
Use GitBook hint syntax for callouts:
```
{% hint style="info" %}
For private GitHub repos, connect GitHub first in **Profile → Connections**.
{% endhint %}
```
Available styles: `info`, `warning`, `success`, `danger`. Use sparingly — usually one per page.

### Tips list
The `## Tips for success` section uses the checkmark format:
```
✅ **Mention Trent in prompts** to make the routing clear

✅ **Re-run scans after meaningful changes** to confirm fixes and update priorities
```
One line per tip. Bold title, then plain explanation. No bullet markers.

### Code blocks
Always tag the language. Keep examples minimal and runnable.
```python
configuration.api_key['apiKey'] = os.environ["TRENT_API_KEY"]
```

Use environment variables for secrets — never hardcode.

### Tables
Use for: parameter lists, response fields, comparison of options, error codes, severity definitions.
Do not use for: prose that flows naturally as paragraphs.

---

## Page Anatomy

Every page follows this skeleton. See `section-patterns.md` for the full set of reusable section templates.

```
---
description: One-sentence summary (optional)
---

# Page Title

One-sentence subtitle that explains what this page covers.

***

## First major section

Content...

***

## Next major section

Content...

***

### Need Help?

* Visit the [Help Centre](../support/help-centre.md) for support
```

---

## Vocabulary

The canonical product names, severities, lifecycle states, and UI labels live in `terminology.md`. Read that file every run before generating content. Do not invent variants.

When a deprecated name appears in source PR titles or commit messages, translate it to the canonical name in generated docs. Flag deprecated names in validation but do not fail the run — historical references in changelogs are legitimate.

---

## Change Templates

Quick reference. Full templates with example phrasing live in `section-patterns.md`.

| Category | Template anchor |
|----------|-----------------|
| `BREAKING_CHANGE` | Migration notice at top, "What Changed", "What You Need to Do", "Timeline" |
| `NEW_FEATURE` | Feature heading, one-sentence summary, "How to use it", "Example" |
| `BEHAVIOR_CHANGE` | "What changed", "Impact", "Action required" |
| `DEPRECATION` | Deprecation notice, "Replacement", "Sunset date", "Migration" |

---

## What NOT to Include

- Raw diffs or code from source repos
- Internal file paths (`src/api/handlers/...`)
- Stack traces — summarize the error instead
- Author names or PR numbers in prose — put them in PR body metadata only
- Implementation details customers don't need
- Internal service names, AWS resource IDs, infrastructure identifiers
- Anything that looks like a secret or credential

---

## File Structure in the docs target

The docs target follows this layout (mirrors the live trent-ai GitBook):

```
README.md
SUMMARY.md
help-centre.md
getting-started/
  quickstart.md
products/
  threat-assessor/
    README.md
    quickstart.md
    create-and-scan-a-project.md
    review-findings.md
    remediate-and-ship.md
  appsec-advisor/
    README.md
    quickstart.md
  prompt-guard/
    README.md
    concepts.md
    quickstart.md
integrations/
  bolt.new-integration.md
  claude-code-integration.md
  lovable-integration.md
  openclaw-integration.md
api-reference/
  README.md
support/
  help-centre.md
```

`doc_suggestion` paths from the classifier are **relative to this root** —
no `docs/` prefix. The deployment's `config.json` `docs.basePath` value
maps the root above to a subdirectory in the docs repo (for example,
`basePath: "gitbook"` puts everything under `gitbook/` in `trnt-ai/sdks`).

When updating docs:
- Match existing heading structure — update in place
- New features → new section in the relevant product file
- New products → new directory + index file (`README.md`) + `quickstart.md`
- Never rename or delete existing files (breaks GitBook links)
