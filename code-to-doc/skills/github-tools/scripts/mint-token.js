#!/usr/bin/env node
/**
 * GitHub App installation token minter
 * Usage: node mint-token.js
 * Prints the installation token to stdout.
 *
 * Required env vars:
 *   GITHUB_APP_ID
 *   GITHUB_APP_PRIVATE_KEY_FILE   (path to full PEM private key file)
 *   GITHUB_INSTALLATION_ID
 */

const https = require('https');
const crypto = require('crypto');
const fs = require('fs');

function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function makeJwt(appId, privateKeyPem) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = base64url(Buffer.from(JSON.stringify({
    iat: now - 60,
    exp: now + (10 * 60),
    iss: appId
  })));
  const signing = `${header}.${payload}`;
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(signing);
  const sig = base64url(sign.sign(privateKeyPem));
  return `${signing}.${sig}`;
}

function httpsPost(url, headers) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request({
      hostname: parsed.hostname,
      path: parsed.pathname,
      method: 'POST',
      headers
    }, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function main() {
  const appId = process.env.GITHUB_APP_ID;
  const privateKeyFile = process.env.GITHUB_APP_PRIVATE_KEY_FILE;
  const installationId = process.env.GITHUB_INSTALLATION_ID;

  if (!appId || !privateKeyFile || !installationId) {
    process.stderr.write('Missing required env vars: GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY_FILE, GITHUB_INSTALLATION_ID\n');
    process.exit(1);
  }

  let privateKey;
  try {
    privateKey = fs.readFileSync(privateKeyFile, 'utf8');
  } catch (e) {
    process.stderr.write(`Failed to read PEM file at ${privateKeyFile}: ${e.message}\n`);
    process.exit(1);
  }

  const jwt = makeJwt(appId, privateKey);
  const result = await httpsPost(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      'Authorization': `Bearer ${jwt}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'openclaw-github-tools/1.0'
    }
  );

  process.stdout.write(result.token + '\n');
}

main().catch(e => {
  process.stderr.write(e.message + '\n');
  process.exit(1);
});
