# Cloudformation file explained

```

Parameters:

# 'staging' --> sent to cloudwatch logs
Environment

# select 2 public subnets for the load balancer
SubnetId 

# the ECS cluster(this should have already been created)
Cluster

# the docker image (tryretool/backend:X.Y.Z, where X.Y.Z is a specific Retool version number. To get help choosing a version number, see [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions).)
Image 

# default number of tasks to run
DesiredCount 

# maximum number of tasks that are allowed to be RUNNING or PENDING during an update
MaximumPercent 

# lower limit number of tasks that must remain RUNNING during update
MinimumHealthyPercent

# the VPC in which to run Retool
VpcId 

# Used to force the deployment even when the image and parameters are otherwised unchanged
Force 

Resources:

# creates a security group for the load balancer
ALBSecurityGroup

# creates an inbound rule for ALBSecurityGroup listening on port 80
GlobalHttpInbound

# creates Cloudwatch logs for monitoring the Retool container
CloudwatchLogsGroup

# creates a security group for the Retool DB
RDSSecurityGroup

# creates an inbound rule for RDSSecurityGroup listening on port 5432
RetoolECSPostgresInbound

# ECS Tasks are basically blueprints for how to run a containerized app (e.g. which docker image to use, which ports to open, any necessary volumes, environment variables, etc.)
# specify the Retool Task with the container tryretool/backend, the cloudwatch logs group specified above, the necessary env variables, the port mapping 80:3000, and the command to start the retool server
RetoolTask

# retool environment variable
RetoolJWTSecret

# retool environment variable
RetoolEncryptionKeySecret

# retool environment variable
RetoolRDSSecret

# The retool database
RetoolRDSInstance

# create an internet-facing load balancer to sit in front of the retool server
# requires 2 public subnets in 2 different availability zones
ECSALB

# a listener for the load balancer, listening on port 80
ALBListener

# add a listener rule for the load balancer, forwarding requests to a specific target group
ECSALBListenerRule

# the target group that the load balancer forwards requests to; receives traffic on port 80
ECSTG

# an ECS service can run multiple ECS tasks and makes sure the correct number of tasks are always running
# runs RetoolTask the number of times specified in DesiredCount
RetoolECSservice

# create an IAM role for the ECS Service
RetoolServiceRole

# create an IAM role for the ECS Task
RetoolTaskRole

# create the Application Load Balancer DNS URL by which to access retool in a browser
Outputs
```

---

# retool-r2.ec2.yaml — Retool + Workflows + R2 (agent sandbox) on ECS-on-EC2

`retool-r2.ec2.yaml` is a self-contained ECS-on-EC2 stack. Unlike the other
templates it **creates its own ECS cluster and EC2 capacity** because the R2
agent sandbox runs gVisor (`runsc --rootless`) inside ephemeral containers, which
needs `/dev/net/tun` and a relaxed seccomp profile on the host (see
*ECS seccomp limitation* below).

On top of the standard Retool + Workflows + Temporal services it adds:

| Component | Purpose | Pool | Port |
| --- | --- | --- | --- |
| `agent-sandbox-controller` | Orchestrates sandbox lifecycle via ECS `RunTask` (`ORCHESTRATOR=ecs`) | platform | 3018 |
| `agent-sandbox-proxy` | Sandbox WebSocket / egress proxy (internal; reached by the backend) | platform | 3019 |
| `retool-agent-sandbox` task def | Pre-registered family the controller launches per sandbox | sandbox | 3017 → dynamic host port |
| `js-executor` | Serverless functions (nsjail) | sandbox (pinned) | 3000 |
| `r2-agent-worker` | Server-side agent loop (Temporal queue `r2-agent`) | platform | — |
| `RrSnapshotsBucket` / `RrGitBucket` | S3 snapshot + RR-git storage | — | — |

## How it fits together

- **Two EC2 capacity pools** share the cluster. The **platform** pool runs the
  awsvpc services (Retool, Workflows, Temporal, code-executor, controller,
  proxy, r2-agent-worker) with Docker's stock security defaults. The **sandbox**
  pool runs the bridge-networked, `RunTask`'d sandboxes *and* the js-executor
  (pinned there by placement constraint); its UserData loads `/dev/net/tun` and
  installs the relaxed gVisor seccomp profile as the Docker daemon default (see
  below), and it carries the `retool.sandbox` ECS attribute so only sandbox-pool
  tasks land there. Capacity-provider binding keeps platform services off sandbox
hosts; the sandbox task definition's `memberOf` placement constraint keeps
  sandboxes on sandbox hosts. Both capacity providers run with managed
  termination protection **disabled**: the protected variant requires ASG
  scale-in protection, which makes the ASGs undeletable (stack teardown hangs).
  The tradeoff is that a rare scale-in event may terminate instances with
  running tasks — services reschedule automatically.
- **Sandbox networking is bridge + dynamic host port** (containerPort 3017 → an
  ephemeral hostPort). The controller resolves each sandbox at
  `instanceIP:hostPort`. This avoids the per-task ENI ceiling you would hit with
  awsvpc when ENI trunking isn't enabled — and ENI trunking is an account-level
  setting we can't assume in customer accounts. Security groups therefore open
  the ephemeral range (32768–60999) from the controller/proxy to sandbox hosts.

## ECS seccomp limitation

ECS task definitions **cannot set custom seccomp profiles** —
`DockerSecurityOptions` only accepts `apparmor:`, `label:`, `credentialspec:`,
and `no-new-privileges`. Docker's stock default profile blocks the
`unshare`/`clone`/`mount`/`pivot_root` syscalls that rootless gVisor + pasta
(agent sandbox) and nsjail (js-executor) require.

The workaround used here: Docker accepts a daemon-level
**`"seccomp-profile"` key in `daemon.json`** that replaces the built-in default
for every container that doesn't set its own — and ECS containers never set
their own. The sandbox pool's UserData installs
[`gvisor-seccomp.json`](./gvisor-seccomp.json) at `/etc/docker/seccomp.json`,
points `daemon.json` at it, and restarts the daemon at boot (before the ECS
agent places any tasks). Because the placement constraint guarantees only
sandbox-pool tasks run on those hosts, the relaxed default's blast radius is
exactly the containers that need it — and the task definitions stay fully
hardened (non-root, capabilities dropped, `no-new-privileges`, device-cgroup'd
to `/dev/net/tun`, still seccomp-filtered). The alternatives — `Privileged: true`
or `CAP_SYS_ADMIN` — disable seccomp entirely and are strictly weaker; keeping
the fully hardened posture per-task is only possible on Kubernetes
(`securityContext.seccompProfile`), which is why internal R2 deployments run
on EKS.

## Prerequisites you must supply

1. **Agent sandbox JWT keypair (ES256 / P-256).** CloudFormation can't generate
   an EC keypair, so pass it in. Newlines must be `\n`-escaped into a single line:

   ```bash
   openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ae.key
   openssl ec -in ae.key -pubout -out ae.pub
   # escape newlines for the parameter value:
   awk '{printf "%s\\n", $0}' ae.key   # -> AgentSandboxJwtPrivateKey
   awk '{printf "%s\\n", $0}' ae.pub   # -> AgentSandboxJwtPublicKey
   ```

2. **Encryption key** (must match the backend):

   ```bash
   openssl rand -hex 32   # -> AgentSandboxEncryptionKey
   ```

That's it — there is no separate proxy domain or certificate to provision (see
*Browser routing* below).

## Key parameters (beyond the base template)

```
# ECS-optimized AMI; default resolves the latest Amazon Linux 2023 ECS AMI.
EcsAmiId

# Image repository overrides. Tag is always RetoolVersion; defaults are the
# public Docker Hub tryretool/* repos. Override to pull from a private
# registry, e.g.:
#   BackendImageRepository          -> 0123456789.dkr.ecr.us-west-2.amazonaws.com/retool-backend
#   CodeExecutorImageRepository     -> .../retool-code-executor-service
#   AgentSandboxImageRepository     -> .../retool-agent-sandbox-service
#   JsExecutorImageRepository       -> .../retool-js-executor-service
BackendImageRepository / CodeExecutorImageRepository / AgentSandboxImageRepository / JsExecutorImageRepository

# Platform pool sizing (awsvpc services — size for ENI count, not just CPU/RAM).
# Backend-image tasks (backend, workflows backend/worker, r2-agent-worker)
# each reserve 2 vCPU / 6 GB; with jobs-runner, code-executor, the Temporal
# cluster, controller, and proxy, the full default stack reserves ~14 vCPU /
# ~36 GB — which exceeds the default 3x m5.xlarge pool on CPU. Managed scaling
# bursts to PlatformAsgMaxSize automatically; to skip the scale-out window on a
# fresh deployment, pre-size with PlatformAsgDesiredCapacity=4 (4x m5.xlarge)
# or PlatformInstanceType=m5.2xlarge.
PlatformInstanceType / PlatformAsgMinSize / PlatformAsgMaxSize / PlatformAsgDesiredCapacity

# Sandbox pool sizing. Sandboxes are 2 vCPU / 4 GB and bridge-networked, so they
# binpack to the CPU/RAM limit. Size DesiredCapacity for the prewarm pool + headroom.
SandboxInstanceType / SandboxAsgMinSize / SandboxAsgMaxSize / SandboxAsgDesiredCapacity / SandboxInstanceVolumeSize

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
#                   Requires EnableWorkflows=false (enforced by a template Rule).
EnableWorkflows / TemporalBackend

# Optional EventBridge -> SQS task-state watcher (faster reconcile; controller
# polls every 5s otherwise).
EnableTaskEventWatcher

# Internal Cloud Map private DNS namespace for service-discovery hostnames
# (default retoolsvc). A namespace name is a VPC-wide singleton — if the VPC
# already runs another deployment using the default, set a unique name (e.g.
# retoolsvc-r2) and this stack creates its own namespace and hosted zone.
CloudMapNamespaceName

# External base URL of the deployment, required by the backend (BASE_DOMAIN).
# Defaults to the stack's ALB DNS name (http, or https with a CertificateArn);
# set it explicitly if you point your own DNS at the ALB.
BaseDomain

# Postgres engine versions for the main Retool RDS instance and (when
# TemporalBackend=self-hosted) the internal Temporal Aurora Serverless v2
# cluster. AWS periodically removes old minor versions — if deployment fails
# with "Cannot find version", check aws rds describe-db-engine-versions.
PostgresEngineVersion / TemporalPostgresEngineVersion

# DeploymentConfiguration note: with DesiredCount=1, MinimumHealthyPercent=50
# rounds up — ECS must keep the single task running, so updates place the new
# task BEFORE stopping the old one, requiring spare pool capacity for two
# replicas of the task. On a tightly-packed pool this stalls the deployment
# ("unable to stop or start tasks during a deployment because of the service
# deployment configuration"). For single-replica deployments pass
# MinimumHealthyPercent=0 (stop-then-start, brief downtime, no extra capacity
# needed), or pre-provision headroom. With DesiredCount=2+ the 50/150 defaults
# roll cleanly.
MinimumHealthyPercent / MaximumPercent

# Storage encryption for the main Postgres instance and (when
# TemporalBackend=self-hosted) the Temporal Aurora cluster. Default true for
# fresh deployments. Cannot be toggled on an existing RDS resource — set false
# when upgrading in place from an unencrypted database (see Upgrading).
RdsStorageEncrypted

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

Both older templates share every logical ID and resource type with
`retool-r2.ec2.yaml` (retool-workflows.ec2.yaml's 49 resources map 1:1;
retool.yaml's 20 are a subset), so an in-place `aws cloudformation
update-stack` onto this template is supported: databases, secrets, the ALB, the
Cloud Map namespace, IAM roles, and the log group are preserved, nothing is
deleted, and only the parameters below need care. New R2 resources (cluster,
EC2 capacity, sandbox components, buckets) are created by the update.

On the first update-stack, pass parameters that preserve the existing stack
(defaults target fresh deployments):

| Situation | Pass |
| --- | --- |
| Old ALB is internet-facing (both old templates hardcode it) | `AlbScheme=internet-facing` **and** a `CertificateArn` — the template rule requires TLS for internet-facing, and omitting the scheme replaces the ALB with a new DNS name |
| Upgrading from retool.yaml | `ALBSubnetId` set to the old `SubnetId` value — retool.yaml placed the ALB in the app subnets, and a different value replaces the ALB |
| Existing main Postgres | `PostgresEngineVersion` = an available minor ≥ the current one (13.11 → 13.23; 15.10 → 15.19) — don't let the default silently attempt a major upgrade |
| Existing Temporal Aurora (from retool-workflows.ec2.yaml) | `TemporalPostgresEngineVersion` = an available 14.x minor (14.17+) — 14.5 is retired, and Aurora cannot jump majors (14 → 16) in one step |
| Existing database is unencrypted (the old templates never set it) | `RdsStorageEncrypted=false` — otherwise the instances are replaced with new empty ones (the old ones are Retained, but the service would come up against an empty database). Encrypting later requires a pg_dump migration instead |

`RetoolVersion` replaces retool.yaml's `Image` (pass the same tag); the old
`Cluster` parameter is gone — this template creates its own cluster.

Expected during the update: ECS services are recreated onto the new in-stack
cluster (a brief per-service outage, no data loss); afterwards decommission the
old external cluster and its EC2 instances manually.

Post-upgrade, rotate the Retool DB password **if it contains URL-reserved
characters** (`: ? # [ ] %` or spaces — the old templates' secret generator
allowed them; this template embeds the password in `AGENT_SANDBOX_POSTGRES_URL`
and the sandbox controller/proxy will fail to parse it):

```bash
NEWPASS=$(openssl rand -base64 24 | tr -d '"@/\\:?#[]% ')
aws rds modify-db-instance --db-instance-identifier <instance> \
  --master-user-password "$NEWPASS" --apply-immediately
aws secretsmanager put-secret-value --secret-id <retool-rds-secret-arn> \
  --secret-string "{\"username\":\"retool\",\"password\":\"$NEWPASS\"}"
```

Finally, supply the new R2 parameters (agent sandbox JWT keypair, encryption
key, image repositories if using a private registry) per *Prerequisites* above.

## Deploy

The template (~96 KB) exceeds the 51,200-byte inline limit for the
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
    ParameterKey=RetoolVersion,ParameterValue=X.Y.Z-stable \
    ParameterKey=AgentSandboxJwtPublicKey,ParameterValue="$(awk '{printf "%s\\n",$0}' ae.pub)" \
    ParameterKey=AgentSandboxJwtPrivateKey,ParameterValue="$(awk '{printf "%s\\n",$0}' ae.key)" \
    ParameterKey=AgentSandboxEncryptionKey,ParameterValue="$(openssl rand -hex 32)"
```

For a server-side dry run, swap `create-stack` for `create-change-set` and add
`--change-set-name initial` (same flags otherwise; on a stack that already
exists, also add `--change-set-type UPDATE`). Inspect the plan with
`aws cloudformation describe-change-set`, then either
`aws cloudformation execute-change-set` to deploy or
`delete-change-set` (+ `delete-stack` to clear the REVIEW_IN_PROGRESS stub) to
discard. Offline, `cfn-lint cloudformation/retool-r2.ec2.yaml` catches most
issues (expect only the inherited W3005 `DependsOn` warnings).

## Validation / test strategy

1. **Static:** `cfn-lint cloudformation/retool-r2.ec2.yaml` (expect only the
   inherited W3005 `DependsOn` warnings).
2. **Dry plan:** `aws cloudformation create-change-set` against a sandbox account
   to confirm the resource graph resolves without deploying.
 3. **Live smoke (sandbox account):** deploy, then confirm
    - ASG instances register to the cluster, and on a sandbox host `/dev/net/tun`
      and `/etc/docker/seccomp.json` exist and `/etc/docker/daemon.json` sets
      `seccomp-profile` (via SSM Session Manager);
    - the controller fills the prewarm pool (`RunTask`);
    - `/assign` returns a non-3017 `podPort`;
    - the proxy forwards to `instanceIP:hostPort` and an R² session works end-to-end;
    - `StopTask` runs on teardown.
 4. **Watcher:** set `EnableTaskEventWatcher=true` and confirm reconcile latency
    drops; set it back to `false` and confirm the 5s poll still converges.
```
