---
name: doc-style
description: Tone, structure, and messaging framework for trnt-ai customer documentation
version: 1.0.0
user-invocable: false
---

# trnt-ai Documentation Style Guide

Apply these rules whenever generating or updating customer documentation.
This reflects the style of the live trent-ai GitBook docs.

---

## Voice & Tone

**Audience:** Security engineers and developers building applications.
Not: executives, non-technical users, or beginners.

**Voice:**
- Direct and confident — state what things do, not what they "may" or "might" do
- Professional but not formal — clear sentences, no corporate speak
- Helpful — lead with what the reader needs to do, not background context
- Concise — every sentence earns its place

**Avoid:**
- Filler openers ("This guide will help you...", "In this section...")
- Passive voice ("The assessment is run" → "Trent runs the assessment")
- Jargon not defined on first use
- Internal codenames, file paths, or implementation details
- Marketing language ("powerful", "seamless", "revolutionary")

---

## Document Structure

### Page anatomy
```
# Page Title

One-sentence description of what this page covers.

---

## Section Heading

Content...

### Subsection (if needed)
```

### Heading levels
- `#` — Page title only (one per page)
- `##` — Major sections
- `###` — Subsections
- Never go deeper than `###`

---

## Content Patterns

### Quick Start / How-to pages
Follow the trent-ai pattern:
1. **Prerequisites** — short, bulleted, only what's actually needed
2. **Numbered steps** — one action per step, imperative mood ("Click", "Run", "Copy")
3. **Code blocks** — always specify language, keep to real runnable examples
4. **Next Steps** — 2-3 links, no more

### API Reference
- Table format for parameters: `Field | Type | Required | Description`
- Response fields in a table
- Show a real example request + response
- Error codes in a table with plain-English explanation

### Feature docs
- Lead with the capability ("Threat Assessor analyzes...")
- Then: when to use it
- Then: how it works (brief)
- End with: link to Quick Start or API ref

---

## Change Documentation

### Breaking Change
```markdown
> ⚠️ **Breaking Change** — {one sentence summary}

## What Changed

{what the old behavior was, what the new behavior is}

## What You Need to Do

{specific steps the customer must take, numbered}

## Timeline

{when this takes effect, when old behavior stops working}
```

### New Feature
```markdown
## {Feature Name}

{One sentence: what it does and why it matters}

### How to use it

{short how-to or link to Quick Start}

### Example

{code block if applicable}
```

### Behavior Change
```markdown
## Changes to {Feature Name}

**What changed:** {previous behavior} → {new behavior}

**Impact:** {who is affected, what they'll see differently}

**Action required:** {yes/no — if yes, what to do}
```

### Deprecation
```markdown
> 🔔 **Deprecation Notice** — {feature} is deprecated as of {date}

**Replacement:** {what to use instead}

**Sunset date:** {when it will be removed}

**Migration:** {link or steps}
```

---

## Code Examples

- Use Python for SDK examples (matches existing trent-ai docs)
- Always use environment variables for API keys, never hardcode
- Keep examples minimal — show only what's relevant
- Include error handling only when it matters to the example

```python
# Good
configuration.api_key['apiKey'] = os.environ["TRENT_API_KEY"]

# Bad
configuration.api_key['apiKey'] = "sk-abc123..."
```

---

## Tables

Use for: parameter lists, response fields, comparison of options, error codes.
Don't use for: prose that flows naturally as paragraphs.

Standard field table:
```
| Field | Type | Description |
|-------|------|-------------|
| `is_safe` | boolean | Whether the prompt passed safety checks |
| `rules` | array | List of violated rules (if any) |
| `request_id` | string | Unique identifier for the request |
```

---

## What NOT to Include

- Raw diffs or code from source repos
- Internal file paths (`src/api/handlers/...`)
- Stack traces (summarize the error instead)
- Author names or PR numbers in prose (put them in PR body metadata only)
- Implementation details customers don't need
- Anything that looks like a secret or credential

---

## File Structure in docs/

```
docs/
  products/
    threat-assessor/
    appsec-advisor/
    prompt-guard/
      quickstart.md
      concepts.md
      sdks/
        python.md
  getting-started/
    quickstart.md
  api-reference/
    README.md
```

When updating docs:
- Match existing heading structure — update in place
- New features → new section in the relevant product file
- New products → new directory + index file
- Never rename or delete existing files (breaks GitBook links)
