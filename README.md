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

[Install](#install) &#8594; [Configure](#configure) &#8594; [Run](#run) &#8594; [Upgrade](#upgrade)

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

2. Save off the `ENCRYPTION_KEY` value, since this is needed to encrypt/decrypt values saved into the Postgres database the Retool instance runs on. 

3. Replace `X.Y.Z-stable` in `Dockerfile` with the desired Retool version listed in our [Dockerhub repo](https://hub.docker.com/r/tryretool/backend/tags), we recommend the latest patch of the most recent [stable version](https://hub.docker.com/r/tryretool/backend/tags?name=stable).

4. To set up HTTPS, you'll need your domain pointing to your server's IP address. If that's in place, make sure `DOMAINS` is correct in `docker.env`, and then set `STAGE=production` in `docker-compose.yml` for the `https-portal` container to attempt to get and use a free `Let's Encrypt` cert for your domain on startup.

> [!WARNING]  
> You must set `COOKIE_INSECURE=true` in `docker.env` to allow logging into Retool without HTTPS configured (not recommended)

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

Upgrade
------

Set the new version in `Dockerfile`, and either run `./upgrade.sh` or follow the below steps:

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
