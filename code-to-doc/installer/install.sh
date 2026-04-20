#!/usr/bin/env bash
set -euo pipefail

# code-to-doc installer for OpenClaw
# Usage: bash installer/install.sh
# Run from the code-to-doc/ directory, or set REPO_ROOT.

# --- paths ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENCLAW_ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
CONFIG_PATH="$OPENCLAW_ROOT/openclaw.json"

AGENTS_ROOT="$OPENCLAW_ROOT/agents"
SHARED_ROOT="$OPENCLAW_ROOT/shared/data"
SKILLS_ROOT="$OPENCLAW_ROOT/skills"

# --- helpers ---

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m✗\033[0m %s\n' "$*"; exit 1; }

# Excludes common to all agent syncs — never overwrite runtime state
AGENT_EXCLUDES=(
  --exclude '.openclaw/'
  --exclude 'memory/'
  --exclude 'state/'
  --exclude 'sessions/'
  --exclude 'agent/'
  --exclude 'WORKING.md'
)

# --- preflight: verify source repo has required files ---

info "Checking source repo..."

source_required=(
  "$REPO_ROOT/agents/orchestrator/AGENTS.md"
  "$REPO_ROOT/agents/change-scanner/AGENTS.md"
  "$REPO_ROOT/agents/doc-classifier/AGENTS.md"
  "$REPO_ROOT/agents/doc-publisher/AGENTS.md"
  "$REPO_ROOT/agents/doc-publisher/publish_docs_pr.py"
  "$REPO_ROOT/shared/data/contracts.md"
  "$REPO_ROOT/shared/data/config.example.json"
  "$REPO_ROOT/skills/github-tools/SKILL.md"
  "$REPO_ROOT/skills/github-tools/scripts/mint-token.js"
  "$REPO_ROOT/skills/customer-facing/SKILL.md"
  "$REPO_ROOT/skills/doc-style/SKILL.md"
)

for filepath in "${source_required[@]}"; do
  [ -f "$filepath" ] || fail "Source file missing: $filepath — is this the correct repo?"
done

ok "Source repo verified"

# --- 1. create directories ---

info "Creating directories..."

mkdir -p \
  "$AGENTS_ROOT/orchestrator" \
  "$AGENTS_ROOT/change-scanner" \
  "$AGENTS_ROOT/doc-classifier" \
  "$AGENTS_ROOT/doc-publisher" \
  "$SHARED_ROOT" \
  "$SKILLS_ROOT"

# --- 2. sync packaged files into live paths ---

info "Syncing agent files..."

rsync -av "${AGENT_EXCLUDES[@]}" \
  "$REPO_ROOT/agents/orchestrator/" \
  "$AGENTS_ROOT/orchestrator/"

rsync -av "${AGENT_EXCLUDES[@]}" \
  "$REPO_ROOT/agents/change-scanner/" \
  "$AGENTS_ROOT/change-scanner/"

rsync -av "${AGENT_EXCLUDES[@]}" \
  "$REPO_ROOT/agents/doc-classifier/" \
  "$AGENTS_ROOT/doc-classifier/"

rsync -av "${AGENT_EXCLUDES[@]}" \
  --exclude '__pycache__/' \
  --exclude 'generated/' \
  --exclude 'pr_body*.md' \
  "$REPO_ROOT/agents/doc-publisher/" \
  "$AGENTS_ROOT/doc-publisher/"

info "Syncing shared data..."

rsync -av \
  --exclude 'config.json' \
  --exclude 'scan-status.json' \
  --exclude 'scan-results.json' \
  --exclude 'classify-status.json' \
  --exclude 'classified-results.json' \
  --exclude 'publish-status.json' \
  "$REPO_ROOT/shared/data/" \
  "$SHARED_ROOT/"

info "Syncing skills..."

rsync -av "$REPO_ROOT/skills/customer-facing/" "$SKILLS_ROOT/customer-facing/"
rsync -av "$REPO_ROOT/skills/doc-style/" "$SKILLS_ROOT/doc-style/"
rsync -av "$REPO_ROOT/skills/github-tools/" "$SKILLS_ROOT/github-tools/"

ok "Files synced"

# --- 3. create config.json from template if missing ---

if [ ! -f "$SHARED_ROOT/config.json" ]; then
  cp "$REPO_ROOT/shared/data/config.example.json" "$SHARED_ROOT/config.json"
  ok "Created $SHARED_ROOT/config.json from config.example.json"
  warn "Edit config.json to set your source repos and docs target before first run"
else
  ok "config.json already exists — not overwriting"
fi

# --- 4. create minimal WORKING.md files if missing ---

for f in \
  "$AGENTS_ROOT/orchestrator/WORKING.md" \
  "$AGENTS_ROOT/change-scanner/WORKING.md"
do
  if [ ! -f "$f" ]; then
    cat > "$f" <<'EOF'
# WORKING.md

last_run: null
status: idle
notes:
- created by installer
EOF
    ok "Created $(basename "$(dirname "$f")")/WORKING.md"
  fi
done

# --- 5. collect GitHub App credentials ---

CREDENTIALS_DIR="$OPENCLAW_ROOT/credentials"
PEM_PATH="$CREDENTIALS_DIR/github-app.pem"
SECRETS_PATH="$OPENCLAW_ROOT/secrets.json"

GITHUB_APP_ID_VAL=""
GITHUB_INSTALLATION_ID_VAL=""
SKIP_CREDS_UPDATE=0

if [ -f "$PEM_PATH" ] && [ -f "$SECRETS_PATH" ]; then
  ok "GitHub App credentials already configured ($PEM_PATH, $SECRETS_PATH)"
  info "To rotate, remove $PEM_PATH and $SECRETS_PATH, then re-run the installer."
  SKIP_CREDS_UPDATE=1
else
  info "Setting up GitHub App credentials..."
  mkdir -p "$CREDENTIALS_DIR"
  chmod 700 "$CREDENTIALS_DIR"

  if [ ! -e /dev/tty ]; then
    fail "No terminal available — run the installer interactively to set GitHub App credentials."
  fi

  printf 'GitHub App ID: ' > /dev/tty
  IFS= read -r GITHUB_APP_ID_VAL < /dev/tty
  [ -n "$GITHUB_APP_ID_VAL" ] || fail "GitHub App ID is required"

  printf 'GitHub Installation ID: ' > /dev/tty
  IFS= read -r GITHUB_INSTALLATION_ID_VAL < /dev/tty
  [ -n "$GITHUB_INSTALLATION_ID_VAL" ] || fail "GitHub Installation ID is required"

  printf "Paste the GitHub App private key (PEM), then type 'END' on its own line:\n" > /dev/tty
  PEM_CONTENT=""
  while IFS= read -r line; do
    [ "$line" = "END" ] && break
    PEM_CONTENT+="$line"$'\n'
  done < /dev/tty

  printf '%s' "$PEM_CONTENT" | grep -q '^-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    || fail "PEM content invalid — missing BEGIN line"
  printf '%s' "$PEM_CONTENT" | grep -q '^-----END [A-Z ]*PRIVATE KEY-----' \
    || fail "PEM content invalid — missing END line"

  ( umask 077 && printf '%s' "$PEM_CONTENT" > "$PEM_PATH" )
  chmod 600 "$PEM_PATH"
  ok "Wrote PEM to $PEM_PATH (chmod 600)"
fi

# --- 6. register agents, secrets provider, and SecretRefs in openclaw.json ---

info "Registering agents in openclaw.json..."

# openclaw.json must already exist — created by OpenClaw setup, not by us
if [ ! -f "$CONFIG_PATH" ]; then
  fail "Missing $CONFIG_PATH. Run OpenClaw setup first."
fi

# Back up before modifying — restore on failure
BACKUP_PATH="$CONFIG_PATH.bak.$$"
cp "$CONFIG_PATH" "$BACKUP_PATH"
info "Backed up openclaw.json to $BACKUP_PATH"

# Node script: upserts agents, secrets provider, per-agent SecretRef env blocks,
# and (if new creds collected) writes ~/.openclaw/secrets.json.
# Does NOT remove other agents or touch agents/main.
if OPENCLAW_ROOT="$OPENCLAW_ROOT" \
   CONFIG_PATH="$CONFIG_PATH" \
   SECRETS_PATH="$SECRETS_PATH" \
   PEM_PATH="$PEM_PATH" \
   GITHUB_APP_ID_VAL="$GITHUB_APP_ID_VAL" \
   GITHUB_INSTALLATION_ID_VAL="$GITHUB_INSTALLATION_ID_VAL" \
   SKIP_CREDS_UPDATE="$SKIP_CREDS_UPDATE" \
   node <<'NODE'
const fs = require('fs');
const path = require('path');

const openclawRoot = process.env.OPENCLAW_ROOT;
const configPath = process.env.CONFIG_PATH;
const secretsPath = process.env.SECRETS_PATH;
const pemPath = process.env.PEM_PATH;
const skipCreds = process.env.SKIP_CREDS_UPDATE === '1';

const desiredAgents = [
  { id: 'orchestrator',    workspace: path.join(openclawRoot, 'agents', 'orchestrator') },
  { id: 'change-scanner',  workspace: path.join(openclawRoot, 'agents', 'change-scanner') },
  { id: 'doc-classifier',  workspace: path.join(openclawRoot, 'agents', 'doc-classifier') },
  { id: 'doc-publisher',   workspace: path.join(openclawRoot, 'agents', 'doc-publisher') },
];

const githubEnvRefs = {
  GITHUB_APP_ID:               { source: 'file', provider: 'filemain', id: '/github/appId' },
  GITHUB_INSTALLATION_ID:      { source: 'file', provider: 'filemain', id: '/github/installationId' },
  GITHUB_APP_PRIVATE_KEY_FILE: { source: 'file', provider: 'filemain', id: '/github/pemPath' },
};

const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);

// --- merge ~/.openclaw/secrets.json with collected values ---
if (!skipCreds) {
  let secrets = {};
  if (fs.existsSync(secretsPath)) {
    try { secrets = JSON.parse(fs.readFileSync(secretsPath, 'utf8')); } catch (_) { secrets = {}; }
  }
  if (!secrets.github || typeof secrets.github !== 'object') secrets.github = {};
  secrets.github.appId = process.env.GITHUB_APP_ID_VAL;
  secrets.github.installationId = process.env.GITHUB_INSTALLATION_ID_VAL;
  secrets.github.pemPath = pemPath;
  fs.writeFileSync(secretsPath, JSON.stringify(secrets, null, 2) + '\n', { mode: 0o600 });
  fs.chmodSync(secretsPath, 0o600);
  console.log(`  Wrote ${secretsPath} (chmod 600)`);
}

// --- register the filemain secrets provider ---
if (!config.secrets) config.secrets = {};
if (!config.secrets.providers) config.secrets.providers = {};
const desiredProvider = { source: 'file', path: secretsPath, mode: 'json' };
const existingProvider = config.secrets.providers.filemain;
if (JSON.stringify(existingProvider) !== JSON.stringify(desiredProvider)) {
  config.secrets.providers.filemain = desiredProvider;
  console.log('  Registered secrets provider: filemain');
}

// --- upsert agents.list keyed by id ---
if (!config.agents) config.agents = {};
if (!Array.isArray(config.agents.list)) config.agents.list = [];

for (const desired of desiredAgents) {
  let entry = config.agents.list.find(a => a && a.id === desired.id);
  if (entry) {
    entry.workspace = desired.workspace;
    console.log(`  Updated agent: ${desired.id}`);
  } else {
    entry = { ...desired };
    config.agents.list.push(entry);
    console.log(`  Added agent: ${desired.id}`);
  }
  // Defensive cleanup — a prior installer version wrote SecretRefs into
  // agents.list[i].env, which OpenClaw's schema rejects. Strip it so re-runs
  // repair configs left in that bad state.
  if ('env' in entry) {
    delete entry.env;
    console.log(`  Removed invalid env block from agent: ${desired.id}`);
  }
}

// --- wire GitHub SecretRefs into the github-tools skill env block ---
// Per OpenClaw schema, per-skill env (at skills.entries["<skill>"].env) is the
// documented surface for injecting env vars into skill processes.
if (!config.skills) config.skills = {};
if (!config.skills.entries) config.skills.entries = {};
if (!config.skills.entries['github-tools']) config.skills.entries['github-tools'] = { enabled: true };
const ghSkill = config.skills.entries['github-tools'];
if (ghSkill.enabled !== true) ghSkill.enabled = true;
if (!ghSkill.env || typeof ghSkill.env !== 'object') ghSkill.env = {};
for (const [k, v] of Object.entries(githubEnvRefs)) {
  if (JSON.stringify(ghSkill.env[k]) !== JSON.stringify(v)) {
    ghSkill.env[k] = v;
    console.log(`  Wired ${k} into skills.entries["github-tools"].env`);
  }
}

// --- ensure agent-to-agent handoff is enabled and agents are in the allowlist ---
if (!config.tools) config.tools = {};
if (!config.tools.agentToAgent) config.tools.agentToAgent = {};
if (config.tools.agentToAgent.enabled !== true) config.tools.agentToAgent.enabled = true;
if (!Array.isArray(config.tools.agentToAgent.allow)) config.tools.agentToAgent.allow = [];

for (const { id } of desiredAgents) {
  if (!config.tools.agentToAgent.allow.includes(id)) {
    config.tools.agentToAgent.allow.push(id);
    console.log(`  Added to agentToAgent allowlist: ${id}`);
  }
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
console.log(`  Wrote ${configPath}`);
NODE
then
  rm -f "$BACKUP_PATH"
  ok "Agents + secrets registered in openclaw.json"
else
  warn "openclaw.json upsert failed — restoring backup"
  cp "$BACKUP_PATH" "$CONFIG_PATH"
  rm -f "$BACKUP_PATH"
  fail "Failed to update openclaw.json. Original config restored."
fi

# --- 7. validate required files ---

info "Validating installation..."

MISSING=0
required=(
  "$AGENTS_ROOT/orchestrator/AGENTS.md"
  "$AGENTS_ROOT/change-scanner/AGENTS.md"
  "$AGENTS_ROOT/doc-classifier/AGENTS.md"
  "$AGENTS_ROOT/doc-publisher/AGENTS.md"
  "$AGENTS_ROOT/doc-publisher/publish_docs_pr.py"
  "$SHARED_ROOT/contracts.md"
  "$SHARED_ROOT/config.json"
  "$PEM_PATH"
  "$SECRETS_PATH"
  "$SKILLS_ROOT/customer-facing/SKILL.md"
  "$SKILLS_ROOT/doc-style/SKILL.md"
  "$SKILLS_ROOT/github-tools/SKILL.md"
  "$SKILLS_ROOT/github-tools/scripts/mint-token.js"
)

for filepath in "${required[@]}"; do
  if [ -f "$filepath" ]; then
    ok "$(echo "$filepath" | sed "s|$OPENCLAW_ROOT/||")"
  else
    warn "Missing: $filepath"
    MISSING=$((MISSING + 1))
  fi
done

if [ "$MISSING" -gt 0 ]; then
  fail "$MISSING required file(s) missing — install may be incomplete"
fi

ok "All required files present"

# --- 8. restart openclaw gateway ---

info "Reloading OpenClaw secrets and restarting gateway..."

if command -v openclaw &>/dev/null; then
  openclaw secrets reload || warn "secrets reload failed — gateway restart will still pick up new refs"
  openclaw gateway restart
  ok "Gateway restarted"
else
  warn "openclaw command not found — skip gateway restart"
  info "Restart OpenClaw manually to pick up the new agents and secrets"
fi

# --- done ---

echo
ok "Install complete"
info "Agents:      $AGENTS_ROOT/{orchestrator,change-scanner,doc-classifier,doc-publisher}"
info "Skills:      $SKILLS_ROOT/{customer-facing,doc-style,github-tools}"
info "Config:      $SHARED_ROOT/config.json"
info "Secrets:     $SECRETS_PATH (chmod 600)"
info "PEM:         $PEM_PATH (chmod 600)"
info "Registry:    $CONFIG_PATH"
echo
info "Next steps:"
info "  1. Edit $SHARED_ROOT/config.json with your repos (if using template)"
info "  2. Start the orchestrator agent in your OpenClaw session"
info "     (change-scanner and doc-publisher pick up GitHub creds via SecretRef — no shell env needed)"
echo
info "To update agent code later, pull changes and re-run: bash installer/install.sh"
