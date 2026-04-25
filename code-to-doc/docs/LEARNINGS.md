# Deployment notes — hard-won lessons

Non-obvious pitfalls discovered while iterating on [code-to-doc-aws.yaml](code-to-doc-aws.yaml). Read before changing the Network Firewall, bootstrap script, or routing.

## Network Firewall

### 1. Stateful inspection needs both directions of the flow

**Symptom:** Firewall is `IN_SYNC`, routes point to the firewall endpoint, rules exist, but nothing is dropped. Flow logs show `"app_proto": "unknown"` and `"state": "new"`. `tls.sni` is never parsed, so no rule ever matches.

**Cause:** By default, egress goes through the firewall but return traffic from the NAT Gateway uses the VPC local route (10.0.0.0/16 → local) straight back to the instance's ENI, bypassing the firewall. Suricata only sees one direction, can't reassemble TLS, rules can't fire.

**Fix:** Add a more-specific route in the **public subnet's** route table sending instance-subnet CIDR traffic back through the firewall endpoint. That route overrides the implicit local route. See `PublicSubnetFirewallReturnRoute` in the template.

```
Instance (10.0.2.x) → firewall → NAT → IGW → internet          (egress)
internet → IGW → NAT → firewall → Instance                     (return)
```

### 2. `RulesSourceList ALLOWLIST` + `STRICT_ORDER` is broken

The simplified domain-list rule form does **not** reliably drop unmatched traffic under strict rule order — even though AWS docs say it should. The enterprise-recommended pattern is explicit Suricata rules (`RulesString`) with STRICT_ORDER on both rule group and policy, a catch-all `drop tls/http` at the end of the rule string, **plus** `StatefulDefaultActions: [drop_established, alert_established]` on the policy as belt-and-suspenders.

### 3. Suricata keywords rejected in STRICT_ORDER

Network Firewall refuses `priority:N;` and `classtype:...;` inside Suricata rules when the rule group is in STRICT_ORDER. Ordering comes from rule position in the `RulesString`, not a per-rule priority keyword. Error is a generic `parameter is invalid`.

### 4. `nocase` is not allowed on `http.host`

The `http.host` sticky buffer is normalized to lowercase by Suricata. Adding `nocase` returns: *"The hostname buffer is normalized to lowercase, specifying nocase is redundant"* — and the entire rule is rejected. Fine on `tls.sni`, not on `http.host`.

### 5. `StatefulRuleOptions.RuleOrder` is effectively immutable

Once a rule group is created with a given `RuleOrder`, switching between `STRICT_ORDER` and `DEFAULT_ACTION_ORDER` via update-stack returns `parameter is invalid`. If you really need to switch, delete the rule group (which requires detaching from the policy first).

### 6. `dotprefix` for domain matching

Use `tls.sni; dotprefix; content:".example.com"; endswith;` — matches both `example.com` and any subdomain (`a.b.example.com`), but **not** `evilexample.com`. Bare `endswith:".example.com"` would fail to match exact `example.com`. Bare `endswith:"example.com"` would match `evilexample.com` (false allow).

### 7. CloudWatch Logs resource policy is required

Without `AWS::Logs::ResourcePolicy` allowing `delivery.logs.amazonaws.com` to write to the log group, the firewall silently fails to deliver alert/flow logs — `aws logs tail` comes back empty even when drops are happening. The policy's `Resource` must cover both the ALERT log group and the `/flow` log group (they're distinct ARNs, the `:*` wildcard only covers log streams).

### 8. Firewall endpoint takes 10–15 min to provision

On initial stack create, the Network Firewall endpoint can come up well after the instance has booted. Bootstrap must wait for internet reachability before running `apt-get`; our loop polls `archive.ubuntu.com` up to 20 minutes. `WaitCondition.Timeout` of 900 s is tight — consider bumping if you add more post-firewall provisioning.

## CloudFormation / bootstrap

### 9. Template > 51 KB requires S3 upload

CLI: use `aws cloudformation deploy --template-file … --s3-bucket …` (auto-uploads). Console: upload via "Upload a template file" (handles large templates transparently). Plain `create-stack --template-body file://…` fails with `Member must have length less than or equal to 51200`.

### 10. `Fn::Sub` escape rules

`${!VarName}` renders literally as `${VarName}` — but the content between `${!` and `}` must only contain alphanumeric, underscore, period, or colon. This means bash default-expansion like `${!var:-default}` is **invalid** because of `:-` and `"`. Use plain `if [ -z "$var" ]; then var=default; fi` blocks instead. Also applies to comments — CFN parses the whole string, doesn't skip shell `#` comments.

### 11. Ubuntu 24.04 AMIs default to regional EC2 mirrors

`/etc/apt/sources.list.d/ubuntu.sources` (DEB822) uses `<region>.ec2.ports.ubuntu.com` / `<region>.ec2.archive.ubuntu.com`. These mirrors **do not respond** when the instance sits behind NAT Gateway + Network Firewall (symptom: connection timeouts on port 80 to 18.x / 34.x EC2 public IPs). Bootstrap rewrites them to the canonical `ports.ubuntu.com` / `archive.ubuntu.com` via `sed` — use `#` as the sed delimiter since the regex contains `(archive|ports)` with `|` alternation.

### 12. Root EBS volume encryption is not automatic

`BlockDeviceMappings /dev/sda1` needs explicit `Ebs.Encrypted: true`. Default depends on account-level EBS encryption setting, which many accounts don't have on.

### 13. IMDSv1 fallback in bootstrap is dead code

`MetadataOptions.HttpTokens: required` forces IMDSv2. The `else` branch in setup.sh that tries the v1 endpoint will never succeed — not broken, just unreachable.

## Debugging

### 14. Always deploy with failure preservation during debug cycles

Rollback terminates the instance and loses `/var/log/openclaw-{bootstrap,setup}.log`. Use:
- Console: *Stack failure options* → **Preserve successfully provisioned resources**
- CLI: `--on-failure DO_NOTHING` on `create-stack` / `--disable-rollback` on `deploy`

### 15. SSM-first diagnostic flow

```bash
export INSTANCE_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK --logical-resource-id OpenClawInstance \
  --query 'StackResources[0].PhysicalResourceId' --output text)

aws ssm start-session --target $INSTANCE_ID
# Then:
sudo -i
tail -F /var/log/openclaw-bootstrap.log /var/log/openclaw-setup.log
```

The last `[N/9]` line in setup log tells you where it stopped. Errors before that pinpoint the failing step.

### 16. Firewall FLOW logs are the definitive inspection telemetry

When blocking isn't working, check `/aws/network-firewall/$STACK/flow`:

- No entries → firewall isn't seeing the traffic (routing bug)
- Entries with `"app_proto": "unknown"` → stateful engine broken (usually asymmetric routing — see #1)
- Entries with `"app_proto": "tls"` and `"alerted": true` → working correctly

### 17. AWS CLI v2 paginates by default

`export AWS_PAGER=""` (or add `cli_pager=` under the profile in `~/.aws/config`) before running any of the diagnostic commands above.

### 18. `$INSTANCE_ID` goes stale across stack recreations

If you redeploy with a new stack name and keep the same shell, `$INSTANCE_ID` likely points at the *previous* stack's instance. Always re-`export INSTANCE_ID=$(...)` after a fresh stack.

## CodeArtifact + npm wrapper

### 19. OpenClaw 2026.4+ does runtime npm-installs at gateway startup

**Symptom:** Gateway "ready" line appears in journal, then nothing. Loopback `curl http://localhost:18789/` accepts the TCP connection but never returns. `systemctl --user status openclaw-gateway` shows a child `npm install …` process under the gateway.

**Cause:** Versions ≥ 2026.4.x install per-extension npm packages on first boot (`@mariozechner/pi-ai`, `@google/genai`, `@clack/prompts`, `partial-json`, …). Those installs run *synchronously* and block Node's event loop, so the HTTP listener accepts but never responds.

**Why it fights the firewall:** The npm tarballs for these packages come from CDN-fronted endpoints (Cloudflare, Fastly) that don't appear under any single allow-listable domain. Allow-listing them is whack-a-mole.

**Fix:** Route npm through **AWS CodeArtifact** with an upstream connection to `public:npmjs`. The instance only talks to the CodeArtifact VPC endpoint (covered by `.amazonaws.com` allow rule). CodeArtifact upstream-fetches via AWS-managed network — bypasses the firewall entirely. Pin to `2026.3.24` if you don't want runtime installs at all (covered in #22).

### 20. The npm wrapper recursion bug

**Symptom:** With CodeArtifact wired up, instance boots fine to "Running cfn-init…", then CPU sits at 60–80% for 30+ minutes, SSM agent goes `ConnectionLost`, setup never completes. Console log buffer fills early so you can't see what's happening.

**Cause:** A naive wrapper that calls `aws codeartifact login --tool npm` on every npm invocation **recurses**. The AWS CLI implements `login --tool npm` by shelling out to `npm config set registry …` internally. That `npm` call resolves through PATH, hits our wrapper, which calls `aws codeartifact login` again, which shells `npm config set …` again. Each level fans out a process tree. Process spawning consumes all CPU.

**Fix:** Sentinel env var that disables the refresh on recursion:
```bash
#!/bin/bash
if [ -z "$_NPM_CA_REFRESH_DONE" ]; then
  AGE=999999
  [ -f "$HOME/.npmrc" ] && AGE=$(( $(date +%s) - $(stat -c %Y "$HOME/.npmrc") ))
  if [ "$AGE" -gt 39600 ]; then  # 11h — CA tokens are valid 12h
    _NPM_CA_REFRESH_DONE=1 aws codeartifact login --tool npm \
      --domain <name> --repository npm-cache --region <region> \
      >/dev/null 2>&1 || true
  fi
fi
exec "$(dirname "$0")/npm-real" "$@"
```

The recursive npm call (triggered by aws cli internally) inherits `_NPM_CA_REFRESH_DONE=1`, sees the sentinel, skips the refresh, just execs npm-real. Recursion breaks cleanly.

### 21. CodeArtifact tokens have a hard 12-hour TTL

`aws codeartifact login` writes an auth token to `~/.npmrc`. Default and **maximum** TTL is 12 hours — there's no flag to extend. Three patterns to handle this:

- **One-shot** (only safe for `2026.3.24`): refresh once during setup.sh. Gateway never calls npm afterward, so the token never matters again.
- **Per-call wrapper** (what we use): refresh in the wrapper if `.npmrc` is older than 11h. Self-healing per call. ~3 ms overhead when fresh, ~1 s when refresh is needed.
- **Systemd timer** (alternative): refresh every 11h in the background. Fewer per-call checks, but if the timer silently fails the gateway hits 401s and you don't notice until something breaks.

The wrapper pattern is more robust because there's no background process whose health you have to monitor.

### 22. Pin `OpenClawVersion` when the firewall must stay tight

`2026.3.24` is the current stable pin: no runtime extension installs, no recursion-prone npm-during-startup behavior. `2026.4.x` (and `latest`) work *with* CodeArtifact + the wrapper, but you'll spend longer on first boot because CodeArtifact has to upstream-fetch every plugin's deps from public npmjs.

When upgrading: deploy on a *staging* stack, watch firewall alerts during plugin install (cold cache), confirm the gateway responds on loopback while installs are running, then promote.

## Bootstrap

### 23. `aws-cfn-bootstrap` needs `pypi.org` + `files.pythonhosted.org`

**Symptom:** Bootstrap fails on `pip3 install … aws-cfn-bootstrap-py3-latest.tar.gz` with `ERROR: Could not find a version that satisfies the requirement chevron`.

**Cause:** The aws-cfn-bootstrap tarball (which we allow via `.amazonaws.com`) declares `chevron`, `python-daemon`, `docutils`, `lockfile` as transitive deps. pip resolves those from `https://pypi.org/simple/` and downloads from `files.pythonhosted.org`. Both domains must be in the firewall allow-list.

**Fix:** Already in the template's rule group as `.pypi.org` and `.pythonhosted.org` pass rules. Don't strip them thinking they're unused.

### 24. WaitCondition timeout depends on instance type

| Instance type | Setup time (cold CA cache) | Recommended `WaitCondition.Timeout` |
|---|---|---|
| `c7g.xlarge` (4 vCPU, 8 GB) — **template default** | 15–25 min, SSM stays online | 2700 s ← current template |
| `c7g.large` (2 vCPU, 4 GB) | 35–50 min — CPU pegs, SSM agent goes offline | bigger instance preferred over longer timeout |
| `t4g.medium` | even slower; SSM agent likely starves | not recommended for fresh deploys |

Fresh deploys (cold CodeArtifact cache) are the worst case. Subsequent stack-update instance replacements are 2–3× faster because most npm packages are cached.

If the SSM agent goes `ConnectionLost` during setup, the instance is alive but can't be debugged via Session Manager. Bigger instance type is the only practical mitigation. After setup completes you can downsize via stack-update.

### 25. Bootstrap silently skips data-volume mount if the volume isn't attached

**Symptom:** New instance after a stack-update has no `~/.openclaw`, no gateway, but setup may otherwise look like it ran.

**Cause:** Step `[0/9] Mounting data volume` looks for `/dev/sdf` / `/dev/nvme1n1`. If the volume isn't attached when the instance boots — common after a manual detach during troubleshooting — `DATA_DEVICE` is unset, the mount block is skipped, and the rest of setup writes to the root volume. Subsequent instance restarts won't pick up the data volume because there's no `/etc/fstab` entry.

**Fix:** When manually detaching the data volume, always re-attach to `/dev/sdf` before stopping/starting the instance. If you've already booted without it, easiest path is to delete the stack and recreate (data volume is `Retain` so it survives — reattach manually to the new instance, or import into the new stack).

### 26. Newer Anthropic Claude models REQUIRE an inference profile

**Symptom:** Gateway logs `Validation error: Invocation of model ID anthropic.claude-sonnet-4-5-… with on-demand throughput isn't supported. Retry your request with the ID or ARN of an inference profile that contains this model.`

**Cause:** Bedrock-side requirement for Claude 3.x+ and 4.x+ — the bare foundation model ID has no on-demand throughput; you must invoke via an inference profile (prefixed `global.` / `us.` / `eu.` / `apac.`). Older Anthropic models (Claude 1, 2, Instant) and most non-Anthropic models (Nova-Lite, Titan, Llama, Mistral) still work with bare IDs.

**Fix:** Set `OpenClawModel` to a prefixed inference profile ID:
- `eu.anthropic.claude-sonnet-4-5-20250929-v1:0` (EU regions only — better data residency)
- `global.anthropic.claude-sonnet-4-5-20250929-v1:0` (cross-region routing — more capacity, possible non-EU traffic)

OpenClaw's plugin auto-discovery enumerates inference profiles via `bedrock:ListInferenceProfiles` (already in our IAM policy), so prefixed IDs work transparently. No config schema change needed — just the model ID itself.

**Why I initially defaulted to bare IDs:** I assumed bare IDs were universally compatible. They're not — Bedrock changed this around the Claude 3 family. The template default is now `eu.anthropic.claude-sonnet-4-5-20250929-v1:0`.

## Acceptance test

From inside the instance, after a successful deploy:

```bash
# Firewall blocking
curl -sS --max-time 5 -o /dev/null https://api.github.com/ ; echo "github: $?"   # expect 0
curl -sS --max-time 5 -o /dev/null https://google.com/     ; echo "google: $?"   # expect 28
curl -sS --max-time 5 -o /dev/null https://bbc.com/        ; echo "bbc:    $?"   # expect 28

# CodeArtifact is the registry
sudo -u ubuntu bash -c '
  export NVM_DIR=/home/ubuntu/.nvm; . $NVM_DIR/nvm.sh
  echo "registry: $(npm config get registry)"
'
# expect: ...d.codeartifact.<region>.amazonaws.com/npm/npm-cache/

# Gateway responsive on loopback
curl -sS -m 5 -o /dev/null -w "loopback: HTTP %{http_code}\n" http://localhost:18789/
# expect: HTTP 200
```

If blocked hosts return 0 instead of 28, re-read #1 before touching anything else.
