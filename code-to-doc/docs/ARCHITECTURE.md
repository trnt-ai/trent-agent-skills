# Architecture

A single-instance OpenClaw deployment on AWS with a tight egress policy. The instance has no public IP. All package installs go through a private npm cache. Browser access is via SSM port-forward only.

## Diagram

```
                 ┌─ your laptop ─┐
                 │ aws ssm       │
                 │ start-session │
                 └───────┬───────┘
                         │ encrypted SSM tunnel
                         │ (control plane: ssm.<region>)
                         │
       ┌─────────────────┼─────────────────────────────────────┐
       │ VPC 10.0.0.0/16 │                                     │
       │                 ▼                                     │
       │     ┌─────────────────────┐                           │
       │     │  EC2 instance       │                           │
       │     │  (private subnet,   │                           │
       │     │   no public IP)     │                           │
       │     │                     │                           │
       │     │  openclaw-gateway   │                           │
       │     │  bound to :18789    │                           │
       │     │  (loopback only)    │                           │
       │     └──────────┬──────────┘                           │
       │                │                                      │
       │   ┌────────────┴───────────────┐                      │
       │   │                            │                      │
       │   ▼ (egress: any 0.0.0.0/0)    ▼ (AWS APIs)           │
       │ ┌────────────────────┐  ┌──────────────────────┐      │
       │ │ Network Firewall   │  │ VPC Interface        │      │
       │ │ stateful, FQDN     │  │ Endpoints:           │      │
       │ │ allow-list:        │  │  - bedrock-runtime   │      │
       │ │  .github.com       │  │  - ssm + ssmmessages │      │
       │ │  .npmjs.org        │  │  - ec2messages       │      │
       │ │  .ubuntu.com       │  │  - codeartifact.api  │      │
       │ │  .amazonaws.com    │  │  - codeartifact.repo │      │
       │ │  .pypi.org         │  └──────┬───────────────┘      │
       │ │  .pythonhosted     │         │                      │
       │ │  …drop everything  │         ▼                      │
       │ │     else           │  ┌──────────────────────┐      │
       │ └─────────┬──────────┘  │ AWS services         │      │
       │           │             │  (Bedrock, SSM,      │      │
       │           ▼             │   CodeArtifact)      │      │
       │     ┌──────────┐        └──────────────────────┘      │
       │     │ NAT GW   │              ▲                       │
       │     │ (egress) │              │ (AWS-managed network) │
       │     └────┬─────┘              │                       │
       │          │                    │ upstream proxy        │
       │          │                    │  to public:npmjs      │
       └──────────┼────────────────────┼───────────────────────┘
                  ▼                    │
              ┌────────┐                │
              │ IGW    │                │
              └───┬────┘                │
                  │                    │
                  ▼                    ▼
           ┌────────────┐       ┌──────────────┐
           │ allowed    │       │ npmjs.org    │
           │ domains    │       │ (only via    │
           │ on the     │       │  CodeArtifact│
           │ public     │       │  upstream)   │
           │ internet   │       │              │
           └────────────┘       └──────────────┘
```

## Resources at a glance

| Resource | Why it exists |
|---|---|
| **EC2 instance** (Ubuntu 24.04, ARM64 c7g.xlarge) | Runs the openclaw gateway and all per-channel plugins as `ubuntu` via systemd user. No public IP. |
| **Private subnet** (10.0.2.0/24) | Where the instance lives. Default route goes through the firewall. |
| **Public subnet** (10.0.1.0/24) | Hosts the NAT Gateway. Has a return-path route back through the firewall (10.0.2.0/24 → firewall) so stateful inspection sees both directions. |
| **Firewall subnet** (10.0.4.0/28) | Dedicated subnet for the Network Firewall endpoint. Routes to NAT. |
| **AWS Network Firewall** | Stateful FQDN allow-list. Drops anything not in the rule list. Logs alerts + flows to CloudWatch. |
| **NAT Gateway** | Outbound NAT for instance traffic destined for the public internet. Receives traffic from the firewall, routes to IGW. |
| **VPC Interface Endpoints** | Private routing for AWS service traffic (Bedrock, SSM, CodeArtifact, EC2Messages). Bypasses the firewall — uses local VPC routing. |
| **Amazon Bedrock** | LLM inference. Called via the bedrock-runtime VPC endpoint. No instance egress to public Anthropic/OpenAI required. |
| **CodeArtifact** (npm-cache repo) | Caches npm packages. Has an upstream connection to public:npmjs which AWS proxies for us. The instance never reaches npmjs.org directly. |
| **EBS data volume** (`/dev/sdf`) | Persists `~/.openclaw` state (channel auth, agent memory) across instance replacements. `DeletionPolicy: Retain`. |
| **SSM Session Manager** | The only access path. No SSH, no public IP. `aws ssm start-session` for shell, `--document-name AWS-StartPortForwardingSession` for browser access to gateway port 18789. |

## Three key flows

### 1. Browser → gateway UI

```
laptop:18789 ──SSM tunnel──▶ instance:18789 (loopback) ──▶ openclaw-gateway
```

SSM Agent on the instance terminates the tunnel and forwards locally to the gateway's loopback listener. Nothing public is exposed; the gateway is bound to `127.0.0.1` only.

### 2. Instance → AWS services (Bedrock, SSM, CodeArtifact)

```
instance ──▶ VPC Interface Endpoint (private DNS) ──▶ AWS service
```

Stays inside the VPC over local routing. Doesn't traverse the firewall. PrivateDnsEnabled means standard service hostnames (`bedrock-runtime.<region>.amazonaws.com` etc.) resolve to the endpoint's private IP automatically.

### 3. Instance → public internet (apt, GitHub API, etc.)

```
instance ──▶ Network Firewall ──▶ NAT Gateway ──▶ IGW ──▶ allowed FQDN
                                                          ▲
                                                          │
              (return path)                               │
              IGW ──▶ NAT ──▶ Network Firewall ──▶ instance
```

Only FQDNs on the allow-list pass. Everything else is dropped at the firewall. **Both directions traverse the firewall** — required for Suricata's stateful TLS inspection to work (see [LEARNINGS.md #1](LEARNINGS.md)).

## What the egress allow-list permits

| FQDN pattern | Why |
|---|---|
| `.github.com`, `.githubusercontent.com` | Git fetch, GitHub API for the doc-publisher agent |
| `.amazonaws.com` | AWS CLI install download, CodeArtifact upstream, AWS API calls not via VPCE |
| `.pypi.org`, `.pythonhosted.org` | `aws-cfn-bootstrap` install at boot pulls deps (chevron, docutils, …) from pypi |
| `.ubuntu.com` | `apt-get update`, `apt-get install` |
| `.npmjs.org` | Legacy/safety; CodeArtifact handles npm now but kept allowed |
| `.docker.com` | Docker CE install if `EnableSandbox=true` |
| `.nodejs.org` | Node.js binaries via NVM |
| `.anthropic.com`, `.openai.com` | Optional, for non-Bedrock model providers |

Everything else: dropped, alerts logged to `/aws/network-firewall/<stack>`.

## Failure modes (and where to look)

| Symptom | First place to look |
|---|---|
| WaitCondition times out | Console output (`aws ec2 get-console-output`), then SSM in if agent is up |
| Gateway unreachable on `localhost:18789` after SSM port-forward | `systemctl --user status openclaw-gateway.service` on instance |
| npm install hangs | Firewall flow log — is anything dropping? CodeArtifact upstream — is package available? |
| Firewall isn't blocking anything | Flow logs show `app_proto: unknown`? See [LEARNINGS.md #1](LEARNINGS.md) — return-path routing |
| SSM `ConnectionLost` | Instance CPU pegged starving the agent. Bigger instance type fixes it. |

## Cost (approx, eu-west-1)

| Item | Monthly |
|---|---|
| EC2 c7g.xlarge | ~$50 |
| EBS root + data | ~$5 |
| Network Firewall endpoint | ~$395 |
| NAT Gateway | ~$32 |
| 7 VPC Interface Endpoints | ~$50 (~$0.01/hr each) |
| CodeArtifact storage | <$1 |
| Bedrock | pay-per-token (variable) |
| **Total fixed** | **~$530–$540** |

The Network Firewall is the dominant cost. If your threat model doesn't require strict egress control, set `EnableNetworkFirewall=false` and total cost drops to ~$60/month, but you lose the FQDN allow-list and the instance returns to a public subnet with a public IP.

## Key design choices

- **Private instance, no public IP.** The only inbound path is SSM Session Manager, which uses outbound-from-agent + AWS service authentication. No SSH key management, no security-group inbound rules.
- **Network Firewall over Security Group egress alone.** Security groups can only filter on IP/port. We need *FQDN* control because LLM/Bedrock CDNs use Cloudflare ranges that can't be expressed as IP rules.
- **CodeArtifact instead of broader firewall allow-list.** npm's tarball CDNs change between OpenClaw versions; allow-listing them all is whack-a-mole. With CodeArtifact, the instance only talks to one AWS endpoint regardless of what npm version brings.
- **Loopback-only gateway + SSM tunnel.** Gateway's auth model is a single bearer token in `~/.openclaw/openclaw.json`. Token theft is mitigated by requiring an AWS-IAM-authenticated SSM tunnel even to reach the port.
- **EBS data volume retained on stack delete.** Recovers state across template iterations. Documented in `EnableDataProtection=true` parameter.

For why each of these isn't simpler, see [LEARNINGS.md](LEARNINGS.md).
