# retool-r2.ec2.yaml — Retool + Workflows + R2 (agent sandbox) on ECS-on-EC2

`retool-r2.ec2.yaml` is a self-contained ECS-on-EC2 stack. It **creates its own
ECS cluster and EC2 capacity** because the R2 agent sandbox runs gVisor
(`runsc --rootless`) inside ephemeral containers, which needs `/dev/net/tun`
and a relaxed seccomp profile on the host (see *ECS seccomp limitation* below).

> **Retool version requirement:** use `4.34.10-stable` or `4.78-edge` or later.
> Older versions do not support the ECS orchestrator this template uses.

On top of the standard Retool + Workflows + Temporal services it adds:

| Component | Purpose | Pool | Port |
| --- | --- | --- | --- |
| `agent-sandbox-controller` | Orchestrates sandbox lifecycle via ECS `RunTask` (`ORCHESTRATOR=ecs`) | platform | 3018 |
| `agent-sandbox-proxy` | Sandbox WebSocket / egress proxy (internal; reached by the backend) | platform | 3019 |
| `<stack>-agent-sandbox` task def | Pre-registered family the controller launches per sandbox | sandbox | 3017 → dynamic host port |
| `js-executor` | Serverless functions (nsjail) | sandbox (pinned) | 3000 |
| `r2-agent-worker` | Server-side agent loop (Temporal queue `r2-agent`) | platform | — |
| `mcp-server` | Model Context Protocol server for external AI clients (same-origin at `/mcp`) | platform | 4010 (internal) |
| `agent-worker` *(optional, `EnableAgents`)* | Retool Agents product runs (Temporal queue `agent`) | platform | — |
| `agent-eval-worker` *(optional, `EnableAgents`)* | Agents dataset evals (Temporal queue `agent-eval`) | platform | — |
| `RrSnapshotsBucket` / `RrGitBucket` / `RrOrgPackagesBucket` | S3 snapshot, RR-git, and org library package tarball storage | — | — |
| `SandboxTaskEventsQueue` + EventBridge rule | Task-state watcher: pushes sandbox task changes to the controller for ~second reconcile (always deployed; the 5s poll is the fallback) | — | — |

## How it fits together

- **Two EC2 capacity pools** share the cluster. The **platform** pool runs the
  awsvpc services with Docker's stock security defaults. The **sandbox** pool
  runs the bridge-networked, `RunTask`'d sandboxes and the js-executor
  (pinned there by placement constraint); its UserData loads `/dev/net/tun`
  and installs the relaxed gVisor seccomp profile as the Docker daemon default
  (see below), and it carries the `retool.sandbox` ECS attribute so only
  sandbox-pool tasks land there. Capacity-provider binding and the sandbox
  task definition's `memberOf` constraint keep the two pools separate. Both
  capacity providers run with managed termination protection **disabled**:
  the protected variant makes the ASGs undeletable (stack teardown hangs), at
  the cost of a rare scale-in possibly terminating instances with running
  tasks — services reschedule automatically.
- **Sandbox networking is bridge + dynamic host port** (containerPort 3017 → an
  ephemeral hostPort). The controller resolves each sandbox at
  `instanceIP:hostPort`. This avoids the per-task ENI ceiling you would hit with
  awsvpc when ENI trunking is not enabled. Security groups therefore open the
  ephemeral range (32768–60999) from the controller/proxy to sandbox hosts.
- **MCP routing is same-origin through the backend relay.** The backend
  frontend forwards `/mcp`, `/.well-known/oauth-*`, and `/api` to the backend
  API, which relays `/mcp` to the mcp-server at `mcp.<namespace>:4010`
  (`MCP_SERVICE_INGRESS_DOMAIN`). Clients connect at `<base-domain>/mcp`; no
  dedicated ALB rule is needed. The mcp-server authenticates bearer tokens
  against `/api/oauth2/introspect` using `OAUTH_INTROSPECTION_AUTH_TOKEN`.
  OAuth and import URLs come from the request's `Host`/`X-Forwarded-Host`,
  which the relay preserves, so `OAUTH_MAIN_DOMAIN` and
  `MCP_SERVICE_EXTERNAL_URL` are not required (`MCP_SERVICE_EXTERNAL_URL`
  remains an optional import override). The ALB idle timeout is 600s so quiet
  MCP SSE streams are not cut mid-tool-call.
- **Retool DB (the Retool Database feature) is backed by the same RDS instance
  as the platform database.** Every backend-family task carries
  `RETOOLDB_POSTGRES_*` pointing at `RetoolRDSInstance` with the master
  credentials from its secret and `RETOOLDB_POSTGRES_SSL=true`. On first setup
  Retool creates its own database and scoped user there; `hammerhead_production`
  is untouched. To isolate Retool DB, point these variables at a dedicated
  Postgres/Aurora cluster.

## ECS seccomp limitation

ECS task definitions **cannot set custom seccomp profiles** —
`DockerSecurityOptions` only accepts `apparmor:`, `label:`, `credentialspec:`,
and `no-new-privileges`. Docker's stock profile blocks the
`unshare`/`clone`/`mount`/`pivot_root` syscalls that rootless gVisor + pasta
(agent sandbox) and nsjail (js-executor) require.

The sandbox pool's UserData works around this by installing
[`gvisor-seccomp.json`](./gvisor-seccomp.json) as the Docker daemon default via
`daemon.json`, before the ECS agent places tasks. Because only sandbox-pool
tasks run on those hosts, the relaxed profile applies only to the containers
that need it; the task definitions themselves stay hardened (non-root,
capabilities dropped, `no-new-privileges`, device-cgroup'd to `/dev/net/tun`,
still seccomp-filtered). `Privileged: true` and `CAP_SYS_ADMIN` would also work
but disable seccomp entirely and are strictly weaker.

## Prerequisites you must supply

1. **Agent sandbox JWT keypair (ES256 / P-256).** CloudFormation can't generate
   an EC keypair, so pass it in. Use the same `cat` form for both create and
   update:

   ```bash
   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ae.key
   openssl ec -in ae.key -pubout -out ae.pub
   # pass the PEM contents directly:
   #   AgentSandboxJwtPrivateKey="$(cat ae.key)"
   #   AgentSandboxJwtPublicKey="$(cat ae.pub)"
   ```

2. **Encryption key** (must match the backend):

   ```bash
   openssl rand -hex 32   # -> AgentSandboxEncryptionKey
   ```

That's it — there is no separate proxy domain or certificate to provision (see
*Browser routing* below).

## Key parameters

```
# ECS-optimized AMI; default resolves the latest Amazon Linux 2023 ECS AMI.
EcsAmiId

# Retool version tag used for every Retool image. Must be 4.34.10-stable or
# 4.78-edge or later; older versions do not support the ECS orchestrator.
RetoolVersion

# Image repository overrides. Tag is always RetoolVersion; defaults are the
# public Docker Hub tryretool/* repos. Override to pull from a private
# registry, e.g.:
#   BackendImageRepository          -> 0123456789.dkr.ecr.us-west-2.amazonaws.com/retool-backend
#   CodeExecutorImageRepository     -> .../retool-code-executor-service
#   AgentSandboxImageRepository     -> .../retool-agent-sandbox-service
#   JsExecutorImageRepository       -> .../retool-js-executor-service
BackendImageRepository / CodeExecutorImageRepository / AgentSandboxImageRepository / JsExecutorImageRepository

# Platform pool sizing. Backend-image tasks reserve 2 vCPU / 6 GB; the full
# default stack needs ~15 vCPU / ~38 GB, more than the default 3x m5.xlarge
# pool. With EnableAgents=true add two more tasks (4 vCPU / 12 GB). ENIs
# bind before CPU/RAM: every platform task is awsvpc, and without ENI
# trunking an m5.xlarge fits 3 task ENIs. The default stack runs 14 platform
# tasks (16 with EnableAgents=true), so it needs 5 hosts (6 with agents).
# Managed scaling bursts to PlatformAsgMaxSize; pre-size with
# PlatformAsgDesiredCapacity=5 (6 with agents) to skip the scale-out window.
PlatformInstanceType / PlatformAsgMinSize / PlatformAsgMaxSize / PlatformAsgDesiredCapacity

# Sandbox pool sizing. Sandboxes are 2 vCPU / 4 GB and bridge-networked, so
# they binpack to the CPU/RAM limit. DesiredCapacity should cover the prewarm
# pool + js-executor tasks + headroom; managed scaling grows the pool as
# sandboxes queue, bounded by MaxSize.
SandboxInstanceType / SandboxAsgMinSize / SandboxAsgMaxSize / SandboxAsgDesiredCapacity / SandboxInstanceVolumeSize

# Agent sandbox controller knobs: prewarm pool size (sandboxes kept warm for
# instant session starts), global cap on concurrent sandbox jobs, and limit on
# in-flight sandbox creates. Defaults: 5 / 50 / 3.
SandboxPrewarmPoolSize / SandboxMaxTotalJobs / SandboxMaxConcurrentCreates

# Per-service task counts. The two executors are independent services with
# independent counts: code-executor (serverless Python blocks, platform pool)
# and js-executor (serverless JS functions, pinned to the sandbox pool for its
# nsjail seccomp needs).
DesiredCount / DesiredWorkflowsCount / DesiredCodeExecutorCount / DesiredJsExecutorCount

# ECS service autoscaling — optional, per executor service, off by default.
# Target-tracking on average CPU utilization across the service's tasks,
# measured against the task definition's Cpu reservation; Min = the service's
# Desired*Count, Max = its *MaxCount. Scale-out cooldown 60s, scale-in 300s.
# Host capacity follows automatically via the capacity providers' managed ASG
# scaling, so scale-out works even from a full pool — tasks sit PENDING until
# the ASG adds instances.
#
# EnableCodeExecutorAutoscaling (platform pool) / CodeExecutorAutoscalingMaxCount / CodeExecutorAutoscalingTargetCpu
# EnableJsExecutorAutoscaling (sandbox pool — leave headroom for the ephemeral
#   sandboxes that share it) / JsExecutorAutoscalingMaxCount / JsExecutorAutoscalingTargetCpu
#
# Deliberately NOT autoscaled: the agent-sandbox controller (it reconciles the
# global prewarm pool; replicas would race on RunTask) and the proxy
# (stateless forwarder). The controller service uses a stop-first deployment
# configuration (MaximumPercent=100, MinimumHealthyPercent=0), with AZ
# rebalancing disabled because ECS rejects maximumPercent <= 100 when it is
# enabled. Ephemeral sandboxes join the sandbox capacity provider, so ECS
# managed scaling grows the ASG as sandboxes queue — set SandboxAsgMinSize to
# your steady-state pool size so a scale-in cannot shrink below it.

# Agent sandbox secrets (see Prerequisites).
AgentSandboxJwtPublicKey / AgentSandboxJwtPrivateKey / AgentSandboxEncryptionKey

# Optional egress allowlist for sandboxes (comma-separated domains).
AllowedDomains

# Workflows + Temporal deployment modes.
#
# EnableWorkflows (default true): deploy the Workflows backend/worker services.
# Requires a Temporal backend (see TemporalBackend). When false, Workflows (the
# product) is unavailable and DesiredWorkflowsCount is inert.
#
# TemporalBackend (default self-hosted):
#   self-hosted     deploy the internal Temporal cluster (5 services + dedicated
#                   Aurora Postgres); Workflows + R2 point at it.
#   retool-managed  skip the internal cluster; Workflows + R2 connect to
#                   Retool-managed Temporal Cloud. WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST
#                   is intentionally left unset (that unset-ness is what selects
#                   the managed path); complete the one-time Temporal Cloud
#                   enrollment in the Retool UI (Settings -> Workflows) after
#                   first login — the namespace + mTLS certs are stored in the
#                   database, not the environment.
#   none            no Temporal anywhere; R2 orchestration runs on pg-boss
#                   against the main Postgres (R2_ORCHESTRATION_BACKEND=postgres).
#                   This requires Retool version 4.78 or later.
#                   Requires EnableWorkflows=false (enforced by a template Rule).
EnableWorkflows / TemporalBackend

# Retool Agents (the product) workers (default false): deploy the agent-worker
# (Temporal queue `agent`) and agent-eval-worker (queue `agent-eval`). Agent
# runs and evals are Temporal workflows with no pg-boss fallback, so
# EnableAgents=true requires a Temporal backend (enforced by the
# AgentsRequireTemporal rule). Prefer EnableWorkflows=true alongside agents.
#
# The Agents product feature itself is also gated by the org-level "AI Agents"
# toggle in Settings -> AI, which is off by default for fresh orgs.
EnableAgents / DesiredAgentsCount

# Internal Cloud Map private DNS namespace for service-discovery hostnames
# (default retoolsvc). A namespace name is a VPC-wide singleton — if the VPC
# already runs another deployment using the default, set a unique name (e.g.
# retoolsvc-r2) and this stack creates its own namespace and hosted zone.
CloudMapNamespaceName

# External base URL of the deployment, required by the backend (BASE_DOMAIN).
# Defaults to the stack's ALB DNS name (http, or https with a CertificateArn);
# set it explicitly if you point your own DNS at the ALB.
BaseDomain

# Retool license key. Required for a usable deployment; the template default is
# an expired trial key and the backend refuses to start with it.
LicenseKey

# Postgres engine versions for the main Retool RDS instance and (when
# TemporalBackend=self-hosted) the internal Temporal Aurora Serverless v2
# cluster. AWS periodically removes old minor versions — if deployment fails
# with "Cannot find version", check aws rds describe-db-engine-versions.
PostgresEngineVersion / TemporalPostgresEngineVersion

# DeploymentConfiguration: MaximumPercent defaults to 200 and
# MinimumHealthyPercent to 50, so a single-task service can start its
# replacement before stopping the old one. On a packed pool the replacement
# stays PENDING and the deployment stalls; pass MinimumHealthyPercent=0 for
# stop-then-start, or pre-provision headroom. Do not lower MaximumPercent below
# 200 for single-task services — ECS rounds 150% of one task down to one.
MinimumHealthyPercent / MaximumPercent

# Storage encryption for the main Postgres instance and (when
# TemporalBackend=self-hosted) the Temporal Aurora cluster. Default false so
# in-place upgrades from retool.yaml / retool-workflows.ec2.yaml do not replace
# the databases. Set true for fresh deployments that require encryption at
# rest; enabling it later requires a pg_dump migration.
RdsStorageEncrypted

# RDS-native deletion protection (default true) for both databases. Disable it
# only for disposable stacks or intentional replacement updates (for example a
# forced engine change): set false, update, then re-enable.
RdsDeletionProtection

# Optional SSH key for capacity instances.
KeyName

# CIDR allowed to reach the ALB on 80/443 (default open), or — preferred for
# Tailscale-gated deployments — the subnet-router instance's SECURITY GROUP via
# AlbIngressSourceSecurityGroupId, which overrides the CIDR when set. Note:
# Tailscale subnet routers SNAT forwarded traffic to their VPC interface IP
# (not their 100.x tailnet IP), so the ALB sees connections from the relay's
# private IP — allow the relay's SG or IP/subnet, not 100.64.0.0/10.
AlbIngressCidr / AlbIngressSourceSecurityGroupId
```

## Browser routing (same-origin)

Self-hosted serves sandbox browser traffic **same-origin through the main
ingress** — there is no separate proxy domain, certificate, or ALB listener. The
backend forwards the sandbox's browser-facing streaming paths
(`/sandbox/:id/agent-ws` WebSocket and `/sandbox/:id/agent-vite` live-preview
assets) to the in-cluster proxy at `AGENT_SANDBOX_PROXY_INGRESS_DOMAIN`, which in
turn reaches the sandbox at `instanceIP:hostPort`. The proxy authenticates every
request via the sandbox token, so forwarding past the main backend's auth
middleware is intentional.

`AGENT_SANDBOX_FRONTEND_WS_PROXY_DOMAIN` is therefore left **unset**, which makes
the backend fall back to the org's base URL. The proxy service is internal
(CloudMap only); it is not attached to the ALB.

## AMI / AppArmor note

The default AMI is **Amazon Linux 2023**, which does not run AppArmor — so the
only host requirements are `/dev/net/tun` and the daemon seccomp profile, both
handled by the sandbox pool's launch template UserData. If you override
`EcsAmiId` with an **Ubuntu** ECS AMI (24.04+), you must also install the
patched `docker-default` AppArmor profile (see `appArmor/` in this repo);
otherwise pasta/runsc fail with `apparmor="DENIED"` on `mount`/`pivot_root`.

## Upgrading from retool.yaml / retool-workflows.ec2.yaml

> **Treat the in-place upgrade as best-effort.** The older templates share
> logical IDs and resource types with this template, which makes an in-place
> `update-stack` possible, but it has not been validated against every existing
> stack configuration. Run a change set first to inspect replacements and
> deletions, or deploy a fresh stack and migrate over.

Choose one of these paths:

1. **Dry-run the in-place update first.** Create a change set (see *Deploy*) and
   inspect the resource changes. Execute it only if no stateful resource — RDS,
   Secrets Manager, or S3 — is being replaced. Take a database snapshot and back
   up the secret values before executing.
2. **Deploy a fresh stack and migrate.** Safer for production: create the new
   stack alongside the old one, migrate the database with `pg_dump` and restore
   into the new stack's database, copy the secret values, verify the new stack,
   then cut DNS over.

An in-place update is intended to preserve databases, secrets, the ALB, the
Cloud Map namespace, IAM roles, and the log group, and to create the new R2
resources (cluster, EC2 capacity, sandbox components, buckets). Verify the
change set rather than assuming this holds for your stack. In particular, stop
if the change set shows `Replacement: True` or `Conditional` for
`AWS::RDS::DBInstance`, `AWS::RDS::DBCluster`, or
`AWS::SecretsManager::Secret`.

The target group is expected to be replaced on the first update. `retool.yaml`
uses an instance target group on port 80, while this template uses an IP target
group on port 3000. Because the new group has no explicit `Name`, CloudFormation
creates it under an auto-generated name, retargets the listeners, and then
removes the old `<stack>-tg` group — no name collision and no manual cleanup.
Upgrading from `retool-workflows.ec2.yaml` (already IP/3000) also replaces the
group because its explicit name is dropped; that cutover is stateless as well.

If you choose the in-place path, pass parameters that preserve the existing
stack (defaults target fresh deployments):

| Situation | Pass |
| --- | --- |
| Old ALB is internet-facing (both old templates hardcode it) | `AlbScheme=internet-facing` **and** a `CertificateArn` — the template rule requires TLS for internet-facing, and omitting the scheme replaces the ALB with a new DNS name |
| Upgrading from retool.yaml | `ALBSubnetId` set to the old `SubnetId` value — retool.yaml placed the ALB in the app subnets, and a different value replaces the ALB |
| Existing main Postgres | `PostgresEngineVersion` = an available minor ≥ the current one (13.11 → 13.23; 15.10 → 15.19) — don't let the default silently attempt a major upgrade |
| Existing Temporal Aurora (from retool-workflows.ec2.yaml) | `TemporalPostgresEngineVersion` = an available 14.x minor (14.17+) — 14.5 is retired, and Aurora cannot jump majors (14 → 16) in one step |
| Existing database is unencrypted (the old templates never set it) | `RdsStorageEncrypted=false` (the default) — otherwise the instances are replaced with new empty ones (the old ones are Retained, but the service would come up against an empty database). Encrypting later requires a pg_dump migration instead |
| Database was deployed without deletion protection (pre-param template) | `RdsDeletionProtection` defaults to true — safe for in-place updates since toggling DeletionProtection on is a no-replacement update; only set false if you intend to replace the instance |

`update-stack --parameters` replaces the entire parameter set: every non-default
value from the existing stack must be passed again. In particular, reuse the
existing `AgentSandboxJwtPublicKey` / `AgentSandboxJwtPrivateKey` /
`AgentSandboxEncryptionKey` values, keep the current `PostgresEngineVersion` and
`TemporalPostgresEngineVersion`, and re-pass any `TemporalBackend`,
`EnableWorkflows`, `EnableAgents`, autoscaling, or sizing overrides. Leave
`MinimumHealthyPercent` at its default 50 unless you deliberately want
stop-first for every service; the agent-sandbox controller already overrides its
own deployment configuration to stop-first.

`RetoolVersion` replaces retool.yaml's `Image` (pass the same tag); the old
`Cluster` parameter is gone — this template creates its own cluster.

If you proceed with the in-place update, expect ECS services to be recreated
onto the new in-stack cluster and a possible brief per-service outage. Verify
the application and the sandbox/MCP paths after the update, then decommission
the old external cluster and its EC2 instances manually.

After deploying (fresh or upgraded), rotate the Retool DB password **if it
contains URL-reserved characters** (`: ? # [ ] %`). The secret generator keeps
the old templates' settings so an in-place upgrade does not regenerate the
secret, which means it can emit these characters; this template embeds the
password in `AGENT_SANDBOX_POSTGRES_URL` and the sandbox controller/proxy will
fail to parse it:

```bash
NEWPASS=$(openssl rand -base64 24 | tr -d '"@/\\:?#[]% ')
aws rds modify-db-instance --db-instance-identifier <instance> \
  --master-user-password "$NEWPASS" --apply-immediately
aws secretsmanager put-secret-value --secret-id <retool-rds-secret-arn> \
  --secret-string "{\"username\":\"retool\",\"password\":\"$NEWPASS\"}"
```

Then pick up the new password everywhere:

- **Agent sandbox controller and proxy:** the password is baked into their
  task definitions at deploy time, and CloudFormation does not notice a changed
  secret value. Run a stack update with a new `Force` value (e.g. a timestamp),
  reusing every other parameter, to re-register both task definitions.
- **Every other service** (backend, jobs-runner, workflows, r2-agent-worker,
  mcp, agents workers) reads the secret at task start. The `Force` update
  redeploys the backend, jobs-runner, workflows, and agents workers;
  r2-agent-worker and mcp have no `FORCE_DEPLOYMENT` variable, so restart them
  with `aws ecs update-service --cluster <stack> --service <service> --force-new-deployment`.

> **Do not change `RetoolRDSSecret`'s `GenerateSecretString` settings in the
> template.** CloudFormation regenerates the secret value when they change but
> leaves the RDS password alone, so every service fails with
> `password authentication failed for user "retool"`.

Finally, supply the new R2 parameters (agent sandbox JWT keypair, encryption
key, image repositories if using a private registry) per *Prerequisites* above.

## Deploy

The example below creates a fresh stack. When updating an existing stack, reuse
the same JWT keypair and `AgentSandboxEncryptionKey`; generating a new
encryption key breaks access to credentials encrypted with the old one.

The template (~140 KB) exceeds the 51,200-byte inline limit for the
`TemplateBody` parameter, so it must be served from S3 via `--template-url`
(this applies to `create-stack`, `update-stack`, `create-change-set`, and
`validate-template` alike):

```bash
BUCKET=retool-ecs-cfn-0123456789 # choose a unique name
aws s3 mb s3://$BUCKET           # run once to create bucket
aws s3 cp cloudformation/retool-r2.ec2.yaml s3://$BUCKET/
TEMPLATE_URL=$(aws s3 presign s3://$BUCKET/retool-r2.ec2.yaml)

aws cloudformation create-stack \
  --stack-name retool-r2-ecs \
  --template-url "$TEMPLATE_URL" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=VpcId,ParameterValue=vpc-xxxx \
    ParameterKey=SubnetId,ParameterValue='"subnet-a,subnet-b"' \
    ParameterKey=ALBSubnetId,ParameterValue='"subnet-pub-a,subnet-pub-b"' \
    ParameterKey=RetoolVersion,ParameterValue=4.34.10-stable \
    ParameterKey=LicenseKey,ParameterValue=YOUR_LICENSE_KEY \
    ParameterKey=RdsStorageEncrypted,ParameterValue=true \
    ParameterKey=AgentSandboxJwtPublicKey,ParameterValue="$(cat ae.pub)" \
    ParameterKey=AgentSandboxJwtPrivateKey,ParameterValue="$(cat ae.key)" \
    ParameterKey=AgentSandboxEncryptionKey,ParameterValue="$(openssl rand -hex 32)"
```

For a server-side dry run, swap `create-stack` for `create-change-set` and add
`--change-set-name initial --change-set-type CREATE` (same flags otherwise;
`create-change-set` defaults to `UPDATE`, which is what an existing stack
needs). Inspect the plan with
`aws cloudformation describe-change-set`, then either
`aws cloudformation execute-change-set` to deploy or
`delete-change-set` (+ `delete-stack` to clear the REVIEW_IN_PROGRESS stub) to
discard.
