# Section Patterns

Reusable section templates that match the live trent-ai GitBook docs.
Use these as the building blocks for any new or updated page.

When you add a new doc type (for example, a `concepts.md` template or a
new SDK guide), add a new section to this file. Don't change `SKILL.md`
unless the voice rules themselves change.

---

## Page Skeleton

Every customer-facing page follows this skeleton.

```markdown
---
description: >-
  One-sentence summary that GitBook surfaces in search and navigation.
---

# Page Title

One-sentence subtitle that explains what this page covers.

***

## First major section

Content...

***

## Common workflows

Content...

***

## Tips for success

✅ **First tip** — explanation

✅ **Second tip** — explanation

***

### Need Help?

* Visit the [Help Centre](../support/help-centre.md) for support
```

The frontmatter `description:` is optional but recommended for product
pages and integration pages. Quickstart pages typically rely on the
subtitle alone.

---

## Standard Sections

These sections appear across most pages. Use the literal phrasing.

### Why it matters

Use as the second section after the page subtitle. Explains motivation
in plain terms — not features, but problems the reader has.

```markdown
## Why it matters

{One short paragraph stating the problem and Trent's role.}

For example:

* {Concrete question the reader is asking}
* {Another concrete question}
* {Third question}

Trent helps answer those questions as you build. {One sentence on how.}

{% hint style="info" %}
This is not just detection. It is ongoing guidance.
{% endhint %}
```

### Prerequisites

Always opens with the exact phrase "Before you begin, you'll need:".

```markdown
## Prerequisites

Before you begin, you'll need:

* Access to [**Trent**](https://app.trent.ai)
* {Second requirement}
* Optional but recommended: {nice-to-have}
```

### Numbered steps

Use `### N. Verb-first heading` for each step. Imperative mood throughout.

```markdown
## How to set up

### 1. Install the package

{Action in one sentence.}

```bash
pip install trentai-mcp
```

***

### 2. Restart your editor

{Why and how, in one or two sentences.}

* **VS Code**: Open the Command Palette → `Developer: Reload Window`
* **Terminal**: Exit and re-enter `claude`
```

### Common workflows

A workflow is a sequence of three to six steps the reader will run
end-to-end. Number the workflows, name them, then list the steps.

```markdown
## Common workflows

### Workflow 1: {Verb-first name}

1. {Step}
2. {Step}
3. {Step}

### Workflow 2: {Verb-first name}

1. {Step}
2. {Step}
3. {Step}
```

### Tips for success

Always uses `✅ **Bold title** — explanation` format. One blank line
between tips. No bullet markers.

```markdown
## Tips for success

✅ **Mention Trent in prompts** to make the routing clear

✅ **Connect GitHub whenever possible** for better context and stronger remediation guidance

✅ **Re-run scans after meaningful changes** to confirm fixes and update priorities

✅ **Review remaining tasks before launch** so you can focus on the highest-impact fixes first
```

### Need Help?

Always the last section. Use `### Need Help?` (subsection heading,
not a top-level section).

```markdown
### Need Help?

* Visit the [Help Centre](../support/help-centre.md) for support
* Visit [trent.ai](https://trent.ai) to learn more
```

---

## Change Templates

One template per change category. Use the matching template when
the doc-classifier emits a change of that category.

### BREAKING_CHANGE

Migration notice goes at the top of the affected section. Always
includes "What Changed", "What You Need to Do", and "Timeline".

```markdown
{% hint style="warning" %}
**Breaking Change** — {one-sentence summary}.
{% endhint %}

## What Changed

{What the old behavior was. What the new behavior is.}

## What You Need to Do

1. {Specific action}
2. {Specific action}
3. {Specific action}

## Timeline

{When this takes effect. When the old behavior stops working.}
```

### NEW_FEATURE

New section added under the matching product page.

```markdown
## {Feature Name}

{One sentence: what it does and why it matters.}

### How to use it

{Short how-to or link to a quickstart.}

### Example

```python
{Minimal runnable example}
```
```

### BEHAVIOR_CHANGE

Update the existing section in place. Use this block when the change
is significant enough to warrant a callout.

```markdown
## Changes to {Feature Name}

**What changed:** {previous behavior} → {new behavior}

**Impact:** {who is affected, what they will see differently}

**Action required:** {yes / no — if yes, what to do}
```

### DEPRECATION

```markdown
{% hint style="warning" %}
**Deprecation Notice** — {feature} is deprecated as of {date}.
{% endhint %}

**Replacement:** {what to use instead}

**Sunset date:** {when it will be removed}

**Migration:** {link or steps}
```

---

## Page Types

Reference layouts for the common page types in `docs/`.

### Product README

Used at `products/{product-slug}/README.md`. Introduces the product.

```markdown
# {Product Canonical Name}

{One-sentence description from terminology.md.}

***

## Why teams use it

{One paragraph framing the problem and Trent's approach.}

***

## What it does

{Numbered list of high-level steps or capabilities.}

1. {Capability}
2. {Capability}
3. {Capability}

***

## Who it is for

* {Audience segment}
* {Audience segment}
* {Audience segment}

***

## Getting started

{One-paragraph entry point with link to quickstart.}

***

## Get started

* [Create and Scan a Project]({slug}/create-and-scan-a-project.md)
* [Review Findings]({slug}/review-findings.md)
* [Remediate and Ship]({slug}/remediate-and-ship.md)
```

### Quickstart

Used at `products/{product-slug}/quickstart.md` and `getting-started/quickstart.md`.

```markdown
# Quick Start

{One-sentence summary of what the reader will accomplish.}

***

## Prerequisites

Before you begin, you'll need:

* Access to [**Trent**](https://app.trent.ai)
* {Other prerequisites}

***

## 1. Sign in to Trent

1. Open [Trent App](https://app.trent.ai)
2. Sign in with your Trent credentials.

***

## 2. {Next step}

{Numbered sub-steps.}

***

## Tips for success

✅ **{Tip}** — {explanation}

✅ **{Tip}** — {explanation}

***

### Need Help?

* Visit the [Help Centre](../../support/help-centre.md) for support
```

### Integration page

Used at `integrations/{tool}-integration.md`.

```markdown
---
description: >-
  Trent's Security Advisor for {Tool}, is a security agent built specifically
  for providing ongoing security advice while building in {Tool}.
---

# {Tool} Integration

## {Tool} Integration

{One-paragraph framing — what {Tool} is for, what Trent adds.}

You build with {Tool}. You secure with Trent.

***

### Why use Trent with {Tool}?

{Motivation paragraph followed by example questions.}

***

### Prerequisites

Before you begin, you'll need:

* Access to [**Trent**](https://app.trent.ai)
* Access to your **{Tool}** workspace and project

***

### 1. Generate your Trent API key

{Steps.}

***

### 2. Configure Trent MCP in {Tool}

{Steps.}

***

### Common workflows

#### Workflow 1: {name}

{Numbered steps.}

***

### Tips for success

✅ **Mention Trent in prompts** to avoid {Tool} handling the request with its native tools

✅ **Connect GitHub whenever possible** for better context and stronger remediation guidance

✅ **Re-run scans after meaningful changes** to confirm fixes and update priorities

***

### Need Help?

* Visit the [Help Centre](../support/help-centre.md) for support
```

### API reference

Used at `api-reference/README.md` or per-endpoint pages.

```markdown
# {Endpoint or API Name}

{One-sentence summary.}

## Authentication

{One paragraph on auth requirements, linking to the auth guide.}

## Request

`POST /v1/{path}`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `field_a` | string | Yes | {Description} |
| `field_b` | boolean | No | {Description} |

### Example

```bash
curl -X POST https://api.trent.ai/v1/{path} \
  -H "x-api-key: $TRENT_API_KEY" \
  -d '{...}'
```

## Response

| Field | Type | Description |
|-------|------|-------------|
| `request_id` | string | {Description} |
| `is_safe` | boolean | {Description} |

### Example

```json
{
  "request_id": "...",
  "is_safe": true
}
```

## Errors

| Code | Meaning |
|------|---------|
| `400` | {Plain-English explanation} |
| `401` | {Plain-English explanation} |
| `429` | {Plain-English explanation} |
```

---

## Adding a New Section Pattern

When the doc-classifier starts emitting a new doc type — for example,
"concepts pages" or "tutorial pages" — add a new section to this file
with:

1. The page skeleton, including frontmatter and the standard outer
   sections (subtitle, separators, Need Help?).
2. A worked example or a link to a representative page in the live
   GitBook.
3. Any vocabulary specific to the new type (added to `terminology.md`,
   not here).

Do not edit `SKILL.md` unless the voice rules themselves change.
