#!/usr/bin/env python3
"""GitHub App installation token minter.

Usage: python3 mint-token.py
Prints the installation token to stdout.

Required env vars:
  GITHUB_APP_ID
  GITHUB_APP_PRIVATE_KEY_FILE   (path to full PEM private key file)
  GITHUB_INSTALLATION_ID

Stdlib only — no third-party deps. Signs the JWT via openssl subprocess
to avoid needing PyJWT or cryptography. Replaces the previous Node
helper, which was hanging indefinitely on https.request() on AL2023
ARM64 hosts (curl, openssl, and Python urllib all work fine on the
same host class).
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def main() -> int:
    app_id = os.environ.get("GITHUB_APP_ID")
    pem_file = os.environ.get("GITHUB_APP_PRIVATE_KEY_FILE")
    installation_id = os.environ.get("GITHUB_INSTALLATION_ID")

    if not all([app_id, pem_file, installation_id]):
        print(
            "Missing required env vars: "
            "GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY_FILE, GITHUB_INSTALLATION_ID",
            file=sys.stderr,
        )
        return 1

    if not os.access(pem_file, os.R_OK):
        print(f"Cannot read PEM file: {pem_file}", file=sys.stderr)
        return 1

    now = int(time.time())
    header = b64url(
        json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode()
    )
    payload = b64url(
        json.dumps(
            {"iat": now - 60, "exp": now + 600, "iss": app_id},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()

    try:
        sig_proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", pem_file, "-binary"],
            input=signing_input,
            capture_output=True,
            timeout=10,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"openssl signing failed: {e.stderr.decode(errors='replace')}", file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print("openssl signing timed out after 10s", file=sys.stderr)
        return 1

    signature = b64url(sig_proc.stdout)
    jwt = f"{header}.{payload}.{signature}"

    req = urllib.request.Request(
        f"https://api.github.com/app/installations/{installation_id}/access_tokens",
        method="POST",
        headers={
            "Authorization": f"Bearer {jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "openclaw-github-tools/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        print(
            f"GitHub API error {e.code}: {e.read().decode(errors='replace')}",
            file=sys.stderr,
        )
        return 1
    except urllib.error.URLError as e:
        print(f"GitHub API request failed: {e.reason}", file=sys.stderr)
        return 1

    try:
        data = json.loads(body)
    except json.JSONDecodeError as e:
        print(f"Failed to parse GitHub response: {e}", file=sys.stderr)
        return 1

    token = data.get("token")
    if not token:
        print(f"Response missing 'token' field: {data}", file=sys.stderr)
        return 1

    print(token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
