<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.retool.com/brand/icons/logo-light.svg">
      <img alt="Retool Logo" height="100" src="https://docs.retool.com/brand/icons/logo-dark.svg">
    </picture>
</p>
<h3 align="center">The best way to build internal software</h3>

<br>

Below are the instructions for deploying with Docker Compose, see [our docs](https://docs.retool.com/docs/deploy-guide-overview) for more specific details for [AWS](https://docs.retool.com/docs/deploy-with-aws-ec2), [GCP](https://docs.retool.com/docs/deploy-with-gcp), or [Azure](https://docs.retool.com/docs/deploy-with-azure-vm), as well as for deploying with [Helm](https://docs.retool.com/docs/deploy-with-helm), [Kubernetes](https://docs.retool.com/docs/deploy-with-kubernetes), or [ECS](https://docs.retool.com/docs/deploy-with-ecs-fargate). Check out our [Community Forums](https://community.retool.com/) if you have questions or issues, and see our [deprecated-onpremise repo](https://github.com/tryretool/deprecated-onpremise) if you need to reference legacy deployment instructions. 

<br>

Deploy with Docker Compose
------

[Install](#install) &#8594; [Configure](#configure) &#8594; [Run](#run) &#8594; [RetoolOS and Slack](#retoolos-and-slack) &#8594; [Upgrade](#upgrade)

<br>

Install
------
> [!IMPORTANT]  
> We test and support running on Ubuntu. If on a different platform, you may need to manually install requirements like Docker.

1. Download this repo

```
git clone https://github.com/tryretool/retool-onpremise retool && cd retool
```

2. Run our install script to attempt to set up Docker and initialize the `.env` files

```
./install.sh
```
The script will create `docker.env` and `retooldb.env` if successful, else it should call out potential issues to address before rerunning.

> [!WARNING]  
> We now assume Compose v2 is installed as a plugin accessed through `docker compose`, we no longer use the legacy v1 `docker-compose` syntax. You may need to use the latter based on your OS and installation, see [Docker's docs](https://docs.docker.com/compose/releases/migrate/) for more context on the migration.

<br>

Configure
------
> [!TIP]  
> Optionally run `sudo usermod -aG docker $USER` and log out/back in to not require `sudo` for every Docker command moving forward. Not required, but we'll assume this in the guide

1. Check the generated `.env` files to make sure the license key and randomized keys were set as expected during the installation.

2. Review the blob storage settings in `docker.env`. The generated defaults use bundled MinIO through `RR_BLOB_STORAGE_PROVIDER=s3` and `RR_DEFAULT_S3_*` variables. For production, replace these with your external object store credentials. For AWS S3, remove `RR_DEFAULT_S3_ENDPOINT` and `AWS_ENDPOINT_URL`; for S3-compatible providers such as MinIO, set both endpoint variables to the provider endpoint.

3. Save off the `ENCRYPTION_KEY` value, since this is needed to encrypt/decrypt values saved into the Postgres database the Retool instance runs on.

4. Replace `X.Y.Z-stable` in `Dockerfile` with the desired Retool version listed in our [Dockerhub repo](https://hub.docker.com/r/tryretool/backend/tags), we recommend the latest patch of the most recent [stable version](https://hub.docker.com/r/tryretool/backend/tags?name=stable).

5. To set up HTTPS, you'll need your domain pointing to your server's IP address. If that's in place, make sure `DOMAINS` is correct in `docker.env`, and then set `STAGE=production` in `compose.yaml` for the `https-portal` container to attempt to get and use a free `Let's Encrypt` cert for your domain on startup.

> [!WARNING]  
> You must set `COOKIE_INSECURE=true` in `docker.env` to allow logging into Retool without HTTPS configured (not recommended)

6. By default, the deployment will include a Temporal container for Workflows. If you have an Enterprise license and would like to instead use Retool's managed Temporal cluster, comment out the `include` block in `compose.yaml` and the `WORKFLOW_TEMPORAL_...` environment variables in `docker.env`. Check out [our docs](https://docs.retool.com/self-hosted/concepts/temporal) for more information on Temporal deployment options.

7. The deployment includes an `mcp` container that serves Retool's [MCP server](https://docs.retool.com/org-users/guides/mcp) at `/mcp`, letting external MCP clients connect to your instance. It needs HTTPS and the `OAUTH_MAIN_DOMAIN`, `MCP_SERVICE_EXTERNAL_URL`, and `OAUTH_INTROSPECTION_AUTH_TOKEN` variables in `docker.env` (all set by `install.sh`). The `https-portal` container routes `/mcp` to it via `CUSTOM_NGINX_SERVER_CONFIG_BLOCK`; the OAuth metadata and introspection endpoints it depends on are served by the `api` service. To disable MCP, remove the `mcp` service and that nginx block from `compose.yaml`. Point your MCP client at `https://<your-domain>/mcp`.

<br>

Run
------

1. Bring up containers
   
```
docker compose up -d
```

2. Check your container statuses after a few minutes

```
docker compose ps
```

3. Check your container logs if any container isn't up and running

```
docker compose logs
```

4. Go to your domain or IP in a browser and click `Sign up` to initialize and log into the new instance

<br>

RetoolOS and Slack
------

After [Install](#install) and [Configure](#configure), use this section **instead of [Run](#run)** to start only the services RetoolOS needs. Confirm with Retool that your license includes RetoolOS. Add `IGNORE_CODE_EXECUTOR_STARTUP_CHECK=true` to `docker.env` before starting the containers. RetoolOS does not use `code-executor`, but `install.sh` configures its URL, so the API would otherwise refuse to start when it cannot reach that service. The flag skips this startup check; Code Executor-backed Workflows will not work until you start `code-executor` and remove the flag.

Slack is optional. If you want to connect it, prepare the Slack app and `docker.env` **before** starting Retool:

1. In `docker.env`, set `BASE_DOMAIN` to your public Retool HTTPS URL, for example `BASE_DOMAIN=https://retool.example.com`. Use that same URL for the Slack redirect URL in the next step.

2. Create a Slack app in the workspace you want to connect. Under **OAuth & Permissions**, add `<your-BASE_DOMAIN>/api/os/messaging/slack/oauth/callback` as a redirect URL. For example, if `BASE_DOMAIN=https://retool.example.com`, use `https://retool.example.com/api/os/messaging/slack/oauth/callback`. Add the bot scopes `assistant:write`, `chat:write`, `im:history`, `im:write`, `users:read`, and `users:read.email`.

3. Under **Basic Information → App-Level Tokens**, generate an `xapp-` token with `connections:write`, then enable [Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode/). Under **Event Subscriptions**, enable events and add the bot event `message.im`. Enable **Interactivity & Shortcuts** for approval buttons. Socket Mode does not require an Events API or Interactivity request URL; the OAuth redirect URL from step 2 is still required.

4. Under [App Home](https://docs.slack.dev/surfaces/app-home/), enable the Messages tab and allow users to send messages. In the app manifest, these settings are `messages_tab_enabled: true` and `messages_tab_read_only_enabled: false`. Without them, Slack may say “Sending messages to this app has been turned off.” Save your Slack app settings.

5. Copy the Client ID, Client Secret, and Signing Secret from **Basic Information**, plus the `xapp-` token from step 3, into `docker.env`:

   ```dotenv
   RETOOLOS_SLACK_CLIENT_ID=YOUR_CLIENT_ID
   RETOOLOS_SLACK_CLIENT_SECRET=YOUR_CLIENT_SECRET
   RETOOLOS_SLACK_SIGNING_SECRET=YOUR_SIGNING_SECRET
   RETOOLOS_SLACK_APP_TOKEN=xapp-YOUR_APP_TOKEN
   ```

   `install.sh` adds these empty entries on a new install. If you already have `docker.env`, add them yourself; the script does not overwrite that file. Keep `docker.env` private because it contains credentials.

Once `docker.env` is ready, start RetoolOS:

```sh
docker compose config --quiet
docker compose up -d \
  api jobs-runner workflows-backend retoolos-temporal-worker \
  js-executor temporal
docker compose ps --all
```

Compose also starts `postgres`, `minio`, and `minio-init` because the selected services depend on them. Wait for Jobs Runner to finish migrations on a new database. The running services should stay up; `minio-init` exiting with code 0 is expected. If RetoolOS does not become ready, start with `docker compose logs --tail=100 api jobs-runner retoolos-temporal-worker` and inspect any other service shown as failed in `ps`. Use [Run](#run) for the full deployment.

Sign in to Retool. Under **Resources**, configure an OpenAI, Anthropic, or Google Gemini resource with your provider credentials. Then, under **Settings → RetoolOS → Configure → Providers for new agents**, select a **Primary provider**. Open RetoolOS and send a short message; confirm you get a reply before connecting Slack. If you instead use Retool's model proxy and see `OPENAI_PROXY_API_TOKEN` missing, contact Retool Support for the token or use your own provider resource. Keep provider keys out of this repository.

If you prepared Slack, finish connecting it now that Retool is running. As a Retool organization admin, open **Settings → RetoolOS → Configure → Messaging → Slack**, select **Add to Slack**, and approve the installation. You should see “Slack connected.” If you change bot scopes after installing the app, reconnect it through Retool to approve the new scopes. DM the bot from a Slack account whose profile email matches an enabled Retool user in this organization with RetoolOS access. A reply confirms the connection. If nothing happens, check `docker compose logs --tail=100 retoolos-temporal-worker`; `inbound sender maps to no Retool user; dropping message` means the email or user access needs fixing.

<br>

Upgrade
------

Set the new version in `Dockerfile`, and either run `./upgrade.sh` or follow the below steps:

> [!NOTE]
> The `mcp` service reads `OAUTH_MAIN_DOMAIN`, `MCP_SERVICE_EXTERNAL_URL`, and `OAUTH_INTROSPECTION_AUTH_TOKEN` from `docker.env`. `install.sh` only writes these on a fresh install, so if you are upgrading an existing deployment add them yourself (see step 7 under [Configure](#configure)). Without them the `mcp` container still starts but MCP clients fail to authenticate.

1. Download and build the new images

```
docker compose build
```

2. Bring up the new containers to replace the old ones

```
docker compose up -d
```

3. Remove the old images from the system
```
docker image prune -a -f
```

<br>
