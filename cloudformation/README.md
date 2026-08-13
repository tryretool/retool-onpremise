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
needs `/dev/net/tun` and a custom seccomp profile on the host.

On top of the standard Retool + Workflows + Temporal services it adds:

| Component | Purpose | Port |
| --- | --- | --- |
| `agent-sandbox-controller` | Orchestrates sandbox lifecycle via ECS `RunTask` (`ORCHESTRATOR=ecs`) | 3018 |
| `agent-sandbox-proxy` | Sandbox WebSocket / egress proxy (internal; reached by the backend) | 3019 |
| `retool-agent-sandbox` task def | Pre-registered family the controller launches per sandbox | 3017 → dynamic host port |
| `js-executor` | Serverless functions (nsjail) | 3000 |
| `r2-agent-worker` | Server-side agent loop (Temporal queue `r2-agent`) | — |
| `RrSnapshotsBucket` / `RrGitBucket` | S3 snapshot + RR-git storage | — |

## How it fits together

- **Two EC2 capacity pools** share the cluster. The **platform** pool runs the
  awsvpc services (Retool, Workflows, Temporal, code/js-executor, controller,
  proxy, r2-agent-worker). The **sandbox** pool runs the bridge-networked,
  `RunTask`'d sandboxes; its UserData loads `/dev/net/tun` and writes
  `/etc/retool/gvisor-seccomp.json`, and it carries the `retool.sandbox` ECS
  attribute so only sandbox tasks land there. Capacity-provider binding keeps
  platform services off sandbox hosts; the sandbox task definition's `memberOf`
  placement constraint keeps sandboxes on sandbox hosts.
- **Sandbox networking is bridge + dynamic host port** (containerPort 3017 → an
  ephemeral hostPort). The controller resolves each sandbox at
  `instanceIP:hostPort`. This avoids the per-task ENI ceiling you would hit with
  awsvpc when ENI trunking isn't enabled — and ENI trunking is an account-level
  setting we can't assume in customer accounts. Security groups therefore open
  the ephemeral range (32768–60999) from the controller/proxy to sandbox hosts.

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

# Platform pool sizing (awsvpc services — size for ENI count, not just CPU/RAM).
PlatformInstanceType / PlatformAsgMinSize / PlatformAsgMaxSize / PlatformAsgDesiredCapacity

# Sandbox pool sizing. Sandboxes are 2 vCPU / 4 GB and bridge-networked, so they
# binpack to the CPU/RAM limit. Size DesiredCapacity for the prewarm pool + headroom.
SandboxInstanceType / SandboxAsgMinSize / SandboxAsgMaxSize / SandboxAsgDesiredCapacity / SandboxInstanceVolumeSize

# Agent sandbox secrets (see Prerequisites).
AgentSandboxJwtPublicKey / AgentSandboxJwtPrivateKey / AgentSandboxEncryptionKey

# Optional egress allowlist for sandboxes (comma-separated domains).
AllowedDomains

# Optional EventBridge -> SQS task-state watcher (faster reconcile; controller
# polls every 5s otherwise).
EnableTaskEventWatcher

# Optional SSH key for capacity instances.
KeyName
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
only host requirements are `/dev/net/tun` and the seccomp profile, both handled
by the launch template UserData. If you override `EcsAmiId` with an **Ubuntu**
ECS AMI (24.04+), you must also install the patched `docker-default` AppArmor
profile (see `appArmor/` in this repo); otherwise pasta/runsc fail with
`apparmor="DENIED"` on `mount`/`pivot_root`.

## Deploy

```bash
aws cloudformation create-stack \
  --stack-name retool-r2 \
  --template-body file://cloudformation/retool-r2.ec2.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=VpcId,ParameterValue=vpc-xxxx \
    ParameterKey=SubnetId,ParameterValue="subnet-a,subnet-b" \
    ParameterKey=ALBSubnetId,ParameterValue="subnet-pub-a,subnet-pub-b" \
    ParameterKey=RetoolVersion,ParameterValue=X.Y.Z-stable \
    ParameterKey=AgentSandboxJwtPublicKey,ParameterValue="$(awk '{printf "%s\\n",$0}' ae.pub)" \
    ParameterKey=AgentSandboxJwtPrivateKey,ParameterValue="$(awk '{printf "%s\\n",$0}' ae.key)" \
    ParameterKey=AgentSandboxEncryptionKey,ParameterValue="$(openssl rand -hex 32)"
```

The template body exceeds the 51,200-byte inline limit for
`aws cloudformation validate-template`; lint it locally with `cfn-lint
cloudformation/retool-r2.ec2.yaml`, or upload to S3 and pass `--template-url` for
a server-side `validate-template` / `create-change-set` dry run.

## Validation / test strategy

1. **Static:** `cfn-lint cloudformation/retool-r2.ec2.yaml` (expect only the
   inherited W3005 `DependsOn` warnings).
2. **Dry plan:** `aws cloudformation create-change-set` against a sandbox account
   to confirm the resource graph resolves without deploying.
3. **Live smoke (sandbox account):** deploy, then confirm
   - ASG instances register to the cluster, and on a sandbox host `/dev/net/tun`
     and `/etc/retool/gvisor-seccomp.json` exist (via SSM Session Manager);
   - the controller fills the prewarm pool (`RunTask`);
   - `/assign` returns a non-3017 `podPort`;
   - the proxy forwards to `instanceIP:hostPort` and an R² session works end-to-end;
   - `StopTask` runs on teardown.
4. **Watcher:** set `EnableTaskEventWatcher=true` and confirm reconcile latency
   drops; set it back to `false` and confirm the 5s poll still converges.
```
