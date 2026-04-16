---
name: github-tools
description: Mint GitHub App installation tokens and call GitHub REST API
version: 1.0.0
user-invocable: false
metadata:
  openclaw:
    requires:
      env:
        - GITHUB_APP_ID
        - GITHUB_APP_PRIVATE_KEY_FILE
        - GITHUB_INSTALLATION_ID
      primaryEnv: GITHUB_APP_PRIVATE_KEY_FILE
---

# GitHub Tools Skill

Provides authenticated access to the GitHub REST API using a GitHub App installation token.
Use this skill for ALL GitHub API calls. Never hardcode tokens.

---

## Token Minting

Mint a fresh installation token at the start of each agent run. Tokens expire after 1 hour.

### Step 1 — Create a JWT

```
iat = now - 60 seconds     (clock skew buffer)
exp = now + 10 minutes
iss = GITHUB_APP_ID
algorithm = RS256
key = contents of GITHUB_APP_PRIVATE_KEY_FILE (PEM file path from env)
```

### Step 2 — Exchange JWT for installation token

```
POST https://api.github.com/app/installations/{GITHUB_INSTALLATION_ID}/access_tokens
Headers:
  Authorization: Bearer {jwt}
  Accept: application/vnd.github+json
  X-GitHub-Api-Version: 2022-11-28
```

Save the returned `token` field. Use it as `Bearer {installation_token}` for all subsequent calls.

### Script Helper

A Node.js helper script is available at `scripts/mint-token.js` in this skill directory.
Run it with: `node <skill_dir>/scripts/mint-token.js`
It reads env vars, loads the PEM from `GITHUB_APP_PRIVATE_KEY_FILE`, and prints the installation token to stdout.

---

## API Conventions

Always include these headers:
```
Authorization: Bearer {installation_token}
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

### Rate Limits
- On `429`: read `Retry-After` header, wait that many seconds, retry
- On `403` with `X-RateLimit-Remaining: 0`: wait until `X-RateLimit-Reset` (unix timestamp)
- Max 3 retries per request, exponential backoff: 1s, 2s, 4s

---

## Common Operations

### List merged PRs since a timestamp
```
GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100
Filter client-side: merged_at >= {since}
```

### Get PR diff/files
```
GET /repos/{owner}/{repo}/pulls/{pull_number}/files
Returns: array of {filename, status, additions, deletions, patch}
```

### Get PR details
```
GET /repos/{owner}/{repo}/pulls/{pull_number}
Returns: title, body, merged_at, merge_commit_sha, user, labels
```

### List directory contents
```
GET /repos/{owner}/{repo}/contents/{path}?ref={branch}
Returns: array of {name, path, type, sha, download_url}
```

### Get file contents
```
GET /repos/{owner}/{repo}/contents/{path}?ref={branch}
Returns: {content} as base64. Decode before use.
```

### Create a branch
```
First get the SHA of the base branch HEAD:
  GET /repos/{owner}/{repo}/git/ref/heads/{base_branch}
  → object.sha

Then create the branch:
  POST /repos/{owner}/{repo}/git/refs
  Body: {"ref": "refs/heads/{new_branch}", "sha": "{base_sha}"}
```

### Commit a file
```
First get the file's current SHA (if it exists):
  GET /repos/{owner}/{repo}/contents/{path}?ref={branch}
  → sha

Then create/update:
  PUT /repos/{owner}/{repo}/contents/{path}
  Body: {
    "message": "{commit message}",
    "content": "{base64 encoded content}",
    "branch": "{branch_name}",
    "sha": "{existing_file_sha}"   ← omit if creating new file
  }
```

### Create a PR
```
POST /repos/{owner}/{repo}/pulls
Body: {
  "title": "{title}",
  "body": "{markdown body}",
  "head": "{branch_name}",
  "base": "main",
  "draft": false
}
```

---

## Repos Reference

| Repo | Owner | Access |
|------|-------|--------|
| HumberAgent | trnt-ai | Read (PRs, files) |
| threat-dashboard | trnt-ai | Read (PRs, files) |
| sdks | trnt-ai | Read + Write (docs/ only) |

Never write to HumberAgent or threat-dashboard. Never write outside `docs/` in sdks.
