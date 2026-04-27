#!/usr/bin/env python3
"""
Doc Publisher — creates a branch, commits multiple doc files, and opens a PR.

Usage:
    python publish_docs_pr.py <manifest.json>

The manifest is a JSON file with this shape:
{
  "token": "ghs_...",
  "repo": "owner/repo",
  "base": "main",
  "branch": "doc-agent/update-2026-04-08",
  "pr_title": "docs: auto-update from recent changes (2026-04-08)",
  "pr_body_file": "/path/to/pr-body.md",
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "files": [
    {"path": "docs/products/foo/quickstart.md", "content_file": "/tmp/foo.md"},
    {"path": "docs/products/bar/overview.md",   "content_file": "/tmp/bar.md"}
  ]
}

Status is written to $OPENCLAW_DATA_DIR/publish-status.json (default /data/openclaw/shared/data/).
"""

import sys
import json
import time
import base64
import datetime
import urllib.request
import urllib.error
from pathlib import Path
from os import environ

DATA_DIR = Path(environ.get('OPENCLAW_DATA_DIR', Path.home() / '.openclaw' / 'shared' / 'data'))
STATUS_PATH = DATA_DIR / 'publish-status.json'

MAX_RETRIES = 3
BACKOFF_BASE = 1  # seconds

HEADERS_TEMPLATE = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'openclaw-doc-publisher/2.0',
}


def write_status(status, *, run_id=None, repo=None, branch=None, **extra):
    payload = {
        'status': status,
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    if run_id:
        payload['run_id'] = run_id
    if repo:
        payload['repo'] = repo
    if branch:
        payload['branch'] = branch
    payload.update(extra)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    STATUS_PATH.write_text(json.dumps(payload, indent=2) + '\n')


def request(method, url, headers, data=None):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method=method)

    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read().decode()
                return r.getcode(), json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read().decode()
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = {'raw': raw}

            if e.code == 429:
                retry_after = int(e.headers.get('Retry-After', BACKOFF_BASE * (2 ** attempt)))
                if attempt < MAX_RETRIES - 1:
                    time.sleep(retry_after)
                    continue
            elif e.code == 403 and e.headers.get('X-RateLimit-Remaining') == '0':
                reset_at = int(e.headers.get('X-RateLimit-Reset', 0))
                wait = max(reset_at - int(time.time()), BACKOFF_BASE * (2 ** attempt))
                if attempt < MAX_RETRIES - 1:
                    time.sleep(min(wait, 60))
                    continue

            return e.code, parsed

    return 0, {'error': 'max retries exceeded'}


def main():
    if len(sys.argv) != 2:
        print('Usage: publish_docs_pr.py <manifest.json>', file=sys.stderr)
        sys.exit(1)

    manifest = json.loads(Path(sys.argv[1]).read_text())
    token = manifest['token']
    repo = manifest['repo']
    base_branch = manifest['base']
    branch = manifest['branch']
    pr_title = manifest['pr_title']
    pr_body = Path(manifest['pr_body_file']).read_text()
    run_id = manifest.get('run_id')
    files = manifest['files']

    headers = {**HEADERS_TEMPLATE, 'Authorization': f'Bearer {token}'}
    result = {'repo': repo, 'base': base_branch, 'branch': branch, 'paths': [f['path'] for f in files]}
    ctx = dict(run_id=run_id, repo=repo, branch=branch)

    write_status('running', **ctx)

    # 1. Get base branch SHA
    code, ref = request('GET', f'https://api.github.com/repos/{repo}/git/ref/heads/{base_branch}', headers)
    result['get_base_ref'] = {'code': code}
    if code != 200:
        result['get_base_ref']['response'] = ref
        write_status('failed', step='get_base_ref', result=result, **ctx)
        print(json.dumps(result, indent=2))
        sys.exit(1)
    base_sha = ref['object']['sha']

    # 2. Create branch (422 = already exists, which is fine for retries)
    code, created = request('POST', f'https://api.github.com/repos/{repo}/git/refs', headers, {
        'ref': f'refs/heads/{branch}',
        'sha': base_sha,
    })
    result['create_branch'] = {'code': code}
    if code not in (201, 422):
        result['create_branch']['response'] = created
        write_status('failed', step='create_branch', result=result, **ctx)
        print(json.dumps(result, indent=2))
        sys.exit(2)

    # 3. Commit each file
    committed = []
    for entry in files:
        path = entry['path']
        content = Path(entry['content_file']).read_text()
        encoded = base64.b64encode(content.encode()).decode()

        # Check if file already exists to get its SHA
        code, existing = request('GET',
            f'https://api.github.com/repos/{repo}/contents/{path}?ref={branch}', headers)
        sha = existing.get('sha') if code == 200 else None

        payload = {
            'message': f'docs: update {Path(path).name}',
            'content': encoded,
            'branch': branch,
        }
        if sha:
            payload['sha'] = sha

        code, put = request('PUT',
            f'https://api.github.com/repos/{repo}/contents/{path}', headers, payload)

        file_result = {'path': path, 'code': code, 'new_file': sha is None}
        if code not in (200, 201):
            file_result['response'] = put
            result.setdefault('commit_files', []).append(file_result)
            write_status('failed', step='commit_file', failed_path=path, result=result, **ctx)
            print(json.dumps(result, indent=2))
            sys.exit(3)

        file_result['commit_sha'] = put.get('commit', {}).get('sha')
        committed.append(file_result)

    result['commit_files'] = committed

    # 4. Create PR
    code, pr = request('POST', f'https://api.github.com/repos/{repo}/pulls', headers, {
        'title': pr_title,
        'body': pr_body,
        'head': branch,
        'base': base_branch,
        'draft': False,
    })
    result['create_pr'] = {'code': code}
    if code not in (200, 201):
        result['create_pr']['response'] = pr
        write_status('failed', step='create_pr', result=result, **ctx)
        print(json.dumps(result, indent=2))
        sys.exit(4)

    pr_url = pr.get('html_url')
    last_sha = committed[-1]['commit_sha'] if committed else None
    paths = [f['path'] for f in files]

    write_status('complete', pr_url=pr_url, commit_sha=last_sha,
                 paths=paths, result=result, **ctx)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
