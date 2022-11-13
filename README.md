<p align="center">
    <a href="https://retool.com/"><img src="https://raw.githubusercontent.com/tryretool/brand-assets/master/Logos/logo-full-black.png" alt="Retool logo" height="100"></a> <br>
    <b>Build internal tools, remarkably fast.</b>
</p> <br>

# Deploying Retool on-premise

[Deploying Retool on-premise](https://docs.retool.com/docs/self-hosted) ensures that all access to internal data is managed within your own cloud environment. It also provides the flexibility to control how Retool is setup within your infrastructure, the ability to configure logging, and access to enable custom SAML SSO using providers like Okta and Active Directory.

## Table of contents

- [Select a Retool version number](#select-a-retool-version-number)
- [One-Click Deploy](#one-click-deploy)
  - [AWS w/ Opta](#one-click-deployment-to-aws-using-opta)
  - [Render](#one-click-deployment-to-render)
- [Single deployments](#single-deployments)
  - [General Machine Specifications](#general-machine-specifications)
  - [AWS w/ EC2](#aws-deploy-with-ec2)
  - [GCP w/ Compute Engine VM](#gcp-deploy-with-compute-engine-virtual-machine)
  - [Azure w/ Azure VM](#azure-deploy-with-azure-virtual-machine)
  - [Heroku](#deploying-retool-on-heroku)
  - [Aptible](#deploying-retool-using-aptible)
- [Managed deployments](#managed-deployments)
  - [General](#general-managed-deployments)
    - [Kubernetes](#deploying-on-kubernetes)
    - [Kubernetes + Helm](#deploying-on-kubernetes-with-helm)
  - [AWS](#amazon-web-services---managed-deployments)
    - [ECS](#deploying-on-ecs)
    - [ECS + Fargate](#deploying-on-ecs-with-fargate)

- [Additional Resources](#additional-resources)
  - [Health check endpoint](#health-check-endpoint)
  - [Troubleshooting](#troubleshooting)
  - [Updating Retool](#updating-retool)
  - [Environment variables](#environment-variables)
  - [Deployment Health Checklist](#deployment-health-checklist)
  - [Docker cheatsheet](#docker-cheatsheet)

## Select a Retool version number

We recommend you set your Retool deployment to a specific version of Retool (that is, a specific semver version number in the format `X.Y.Z`, instead of a tag name). This will help prevent unexpected behavior in your Retool instances. When you are ready to upgrade Retool, you can bump the version number to the specific new version you want.

To help you select a version, see our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions).

## One-Click Deploy

### One-click Deployment to AWS using Opta

Just use the Deploy to AWS button below!

[![Deploy](https://raw.githubusercontent.com/run-x/opta/main/assets/deploy-to-aws-button.svg)](https://app.runx.dev/deploy-with-aws?url=https%3A%2F%2Fgithub.com%2Ftryretool%2Fretool-onpremise%2Fblob%2Fmaster%2Fopta%2Fopta.yaml&name=Retool)

### One-click Deployment to Render

Just use the Deploy to Render button below! Here are [some docs](https://render.com/docs/deploy-retool) on deploying Retool with Render.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/render-examples/retool)

## Single Deployments

### General Machine Specifications
- Linux Virtual Machine
  - Ubuntu `16.04` or higher
- `2` vCPUs
- `8` GiB + of Memory
- `60` GiB + of Storage 
- Networking Requirements for Initial Setup:
  - `80` (http): for connecting to the server from the browser
  - `443` (https): for connecting to the server from the browser
  - `22` (SSH): To allow you to SSH into your instance and configure it
  - `3000` (Retool): This is the default port Retool runs on

### AWS Deploy With EC2

Spin up a new EC2 instance. If using AWS, use the following steps:

1. Click **Launch Instance** from the EC2 dashboard.
1. Click **Select** for an instance of Ubuntu `16.04` or higher.
1. Select an instance type of at least `t3.medium` and click **Next**.
1. Ensure you select the VPC that also includes the databases / API’s you will want to connect to and click **Next**.
1. Increase the storage size to `60` GB or higher and click **Next**.
1. Optionally add some Tags (e.g. `app = retool`) and click **Next**. This makes it easier to find if you have a lot of instances.
1. Set the network security groups for ports `80`, `443`, `22` and `3000`, with sources set to `0.0.0.0/0` and `::/0`, and click **Review and Launch**. We need to open ports `80` (http) and `443` (https) so you can connect to the server from a browser, as well as port `22` (ssh) so that you can ssh into the instance to configure it and run Retool. By default on a vanilla EC2, Retool will run on port `3000`.
1. On the **Review Instance Launch** screen, click **Launch** to start your instance.
1. If you're connecting to internal databases, whitelist the VPS's IP address in your database.
1. From your command line tool, SSH into your EC2 instance.
1. Run the command `git clone https://github.com/tryretool/retool-onpremise.git`.
1. Run the command `cd retool-onpremise` to enter the cloned repository's directory.
1. Edit the `Dockerfile` to set the version of Retool you want to install. To do this, replace `X.Y.Z` in `FROM tryretool/backend:X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.
1. Run `./install.sh` to install Docker and Docker Compose.
1. In your `docker.env` (this file is only created after running `./install.sh`) add the following:

   ```docker
   # License key granted to you by Retool
   LICENSE_KEY=YOUR_LICENSE_KEY

   # This is necessary if you plan on logging in before setting up https
   COOKIE_INSECURE=true
   ```

1. Run `sudo docker-compose up -d` to start the Retool server.
1. Run `sudo docker-compose ps` to make sure all the containers are up and running.
1. Navigate to your server's IP address in a web browser. Retool should now be running on port `3000`.
1. Click Sign Up, since we're starting from a clean slate. The first user to create an account on an instance becomes the administrator.

### GCP Deploy With Compute Engine Virtual Machine

1. Click the Compute Engine Resource from the GCP Dashboard and select VM Instances
1. In the top menu, select ‘Create Instance’
1. Create a new VM to these Specs
    - Ubuntu Operating System Version 16.04 LTS or higher
    - Storage Size 60 GB or higher
    - Ram 4 GB or Higher (e2-medium)
    - Optionally add Labels (eg app = retool)
1. Create Instance
1. Navigate via search to the VPC Network Firewall settings and be sure to add the following ports set to`0.0.0.0/0` and `::/0`
    - `80` (HTTP)
    - `443` (HTTPS)
    - `22` (SSH)
    - `3000` (Retool access in browser)
1. If you're connecting to an internal database, be sure to whitelist the VPC’s ip address in your DB
1. SSH into your instance, or use the Google SSH Button to open a VM Terminal in a browser window.
1. Run Command `git clone https://github.com/tryretool/retool-onpremise.git`
1. Run Command `cd retool-onpremise`
1. Edit the Dockerfile using VIM (or other text editor) to specify your desired version number of Retool. To do this, replace `X.Y.Z` in `FROM tryretool/backend:X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.
1. Run Command `./install.sh` to install docker containers, docker, and docker-compose
1. In your docker.env file (this file will only exist after step 11)
    - Add the license key from `my.retool.com` to replace `YOUR_LICENSE_KEY`
    - If you will need to access your instance before configuring HTTPS, you will need to uncomment the line `COOKIE_INSECURE=true`
1. Run `sudo docker-compose up -d` to start the Retool docker containers
1. Run `sudo docker-compose ps` to see container status and ensure all are running
1. Navigate to your servers IP address or domain in a web browser. Retool will be running on `port 3000`
1. Click Sign Up, since this is a brand new instance. The first user created will become the administrator

### Azure Deploy with Azure Virtual Machine

1. In the main Azure Portal select Virtual Machine under Azure Services
1. Click the Create button and select Virtual Machine 
1. Select an image of Ubuntu 16.04 or higher
1. For instance size, select `Standard_D2s_v3 - 2 vcpus, 8 GiB memory`
1. Under the Networking tab, Ensure you select the same Virtual Network that also includes the databases / API’s you will want to connect to and click **Next**.
1. Under the Networking tab, configure your network security group to contain the following ports. You may need to create a new Security group that contains these 4 ports (`80`, `443`, `22` and `3000`): 
    - `80` (http) and `443` (https) for connecting to the server from a browser 
    - `22` (ssh) to allow you to ssh into the instance and configure it
    - `3000` is the port that Retool runs on by default
1. From your command line tool, SSH into your Azure instance.
1. Run the command `git clone https://github.com/tryretool/retool-onpremise.git`.
1. Run the command `cd retool-onpremise` to enter the cloned repository's directory.
1. Edit the `Dockerfile` to set the version of Retool you want to install. To do this, replace `X.Y.Z` in `FROM tryretool/backend:X.Y.Z` with your desired version. See [Select a Retool version number](https://github.com/tryretool/retool-onpremise#select-a-retool-version-number) to help you choose a version.
1. Run `./install.sh` to install Docker and Docker Compose.
1. In your `docker.env` (this file is only created after running `./install.sh`) add the following:
    
    `# License key granted to you by Retool
    LICENSE_KEY=YOUR_LICENSE_KEY`
    
    `# This is necessary if you plan on logging in before setting up https
    COOKIE_INSECURE=true`
    
1. Run `sudo docker-compose up -d` to start the Retool server.
1. Run `sudo docker-compose ps` to make sure all the containers are up and running.
1. Navigate to your server's IP address in a web browser. Retool should now be running on port `3000`.
1. Click Sign Up, since we're starting from a clean slate. The first user to create an account on an instance becomes the administrator.


### General Single-Instance Deploy

### Deploying Retool on Heroku

#### Automatic deploy

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/tryretool/retool-onpremise)

You can deploy to Heroku using the following steps:

1. Click the button above to begin your deployment
1. Provide a unique App name, e.g. `<your-org>-retool`
1. Provide required config vars:
    * `LICENSE_KEY` - your Retool license key
1. Set any optional config vars:
    * `USE_GCM_ENCRYPTION` set to `true` for authenticated encryption of
      secrets; if true, `ENCRYPTION_KEY` must be 24 bytes
1. Click "Deploy app"

#### Manual deploy

You can manually deploy to Heroku using the following steps:

1. Install the Heroku CLI, and login. Documentation for this can be found here: <https://devcenter.heroku.com/articles/getting-started-with-nodejs#set-up>
1. Clone this repo `git clone https://github.com/tryretool/retool-onpremise`
1. Change the working directory to the newly cloned repository `cd ./retool-onpremise`
1. Create a new Heroku app with the stack set to `container` with `heroku create your-app-name --stack=container`
1. Add a database: `heroku addons:create heroku-postgresql:mini`
1. In the `Settings` page of your Heroku app, add the following environment variables:
   1. `NODE_ENV` - set to `production`
   1. `HEROKU_HOSTED` set to `true`
   1. `JWT_SECRET` - set to a long secure random string used to sign JSON Web Tokens
   1. `ENCRYPTION_KEY` - a long secure random string used to encrypt database credentials
   1. `USE_GCM_ENCRYPTION` set to `true` for authenticated encryption of secrets; if true, `ENCRYPTION_KEY` must be 24 bytes
   1. `LICENSE_KEY` - your Retool license key
   1. `PGSSLMODE` - set to `require`
1. _Optional_: To lockdown the version of Retool used, just edit the first line
   under `./heroku/Dockerfile` to:
   ```docker
   FROM tryretool/backend:X.Y.Z
   ```
1. Push the code: `git push heroku master`

### Deploying Retool using Aptible

1. Add your public SSH key to your Aptible account through the Aptible dashboard
1. Install the Aptible CLI, and login. Documentation for this can be found here: <https://www.aptible.com/documentation/deploy/cli.html>
1. Clone this repo `git clone https://github.com/tryretool/retool-onpremise`
1. Change the working directory to the newly cloned repository `cd ./retool-onpremise`
1. Edit the `Dockerfile` to set the version of Retool you want to install. To do this, replace `X.Y.Z` in `FROM tryretool/backend:X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.
1. Create a new Aptible app with `aptible apps:create your-app-name`
1. Add a database: `aptible db:create your-database-name --type postgresql`
1. Set your config variables (your database connection string will be in your Aptible Dashboard and you can parse out the individual values by following [these instructions](https://www.aptible.com/documentation/deploy/reference/databases/credentials.html#using-database-credentials)). Be sure to rename `EXPIRED-LICENSE-KEY-TRIAL` to the license key provided to you.
1. If secrets need an authenticated encryption method, add `USE_GCM_ENCRYTPION=true` to the command below and change `ENCRYPTION_KEY=$(cat /dev/urandom | base64 | head -c 24)`

   ```yml
   aptible config:set --app your-app-name \
       POSTGRES_DB=your-db \
       POSTGRES_HOST=your-db-host \
       POSTGRES_USER=your-user \
       POSTGRES_PASSWORD=your-db-password \
       POSTGRES_PORT=your-db-port \
       POSTGRES_SSL_ENABLED=true \
       FORCE_SSL=true \
       NODE_ENV=production \
       JWT_SECRET=$(cat /dev/urandom | base64 | head -c 256) \
       ENCRYPTION_KEY=$(cat /dev/urandom | base64 | head -c 64) \
       LICENSE_KEY=EXPIRED-LICENSE-KEY-TRIAL
   ```

1. Set your git remote which you can find in the Aptible dashboard: `git remote add aptible your-git-url`
1. Push the code: `git push aptible master`
1. Create a default Aptible endpoint
1. Navigate to your endpoint and sign up as a new user in your Retool instance

## Managed deployments

Deploy Retool on a managed service. We've provided some starter template files for Cloudformation setups (ECS + Fargate), Kubernetes, and Helm.

### General Managed Deployments

### Deploying on Kubernetes

1. Navigate into the `kubernetes` directory
1. Edit the `retool-container.yaml` and `retool-jobs-runner.yaml` files to set the version of Retool you want to install. To do this, replace `X.Y.Z` in `image: tryretool/backend:X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.
1. Copy the `retool-secrets.template.yaml` file to `retool-secrets.yaml` and inside the `{{ ... }}` sections, replace with a suitable base64 encoded string.
   1. To base64 encode your license key, run `echo -n <license key> | base64` in the command line. Be sure to add the `-n` character, as it removes the trailing newline character from the encoding.
   1. If you do not wish to add google authentication, replace the templates with an empty string.
   1. You will need a license key in order to proceed.
1. Run `kubectl apply -f ./retool-secrets.yaml`
1. Run `kubectl apply -f ./retool-postgres.yaml`
1. Run `kubectl apply -f ./retool-container.yaml`
1. Run `kubectl apply -f ./retool-jobs-runner.yaml`

For ease of use, this will create a postgres container with a persistent volume for the storage of Retool data. We recommend that you use a managed database service like RDS as a long-term solution. The application will be exposed on a public ip address on port 3000 - we leave it to the user to handle DNS and SSL.

Please note that by default Retool is configured to use Secure Cookies - that means that you will be unable to login unless https has been correctly setup.

To force Retool to send the auth cookies over HTTP, please set the `COOKIE_INSECURE` environment variable to `'true'` in `./retool-container.yaml`. Do this by adding the following two lines to the `env` section.

```yaml
        - name: COOKIE_INSECURE
          value: 'true'
```

Then, to update the running deployment, run `$ kubectl apply -f ./retool-container.yaml`

### Deploying on Kubernetes with Helm

See <https://github.com/tryretool/retool-helm> for full Helm chart documentation
and instructions.

### Amazon Web Services - Managed Deployments

### Deploying on ECS

We provide a [template file](/cloudformation/retool.yaml) for you to get started deploying on ECS.

1. In the ECS Dashboard, click **Create Cluster**
1. Select `EC2 Linux + Networking` as the cluster template.
1. In your instance configuration, enter the following:
   - Select **On-demand instance**
   - Select **t2.medium** as the instance type (or your desired instance size)
   - Choose how many instances you want to spin up
   - (Optional) Add key pair
   - Choose your existing VPC (or create a new one)
   - (Optional) Add tags
   - Enable CloudWatch container insights
1. Select the VPC in which you’d like to launch the ECS cluster; make sure that you select a [public subnet](https://stackoverflow.com/questions/48830793/aws-vpc-identify-private-and-public-subnet).
1. Download the [retool.yaml](/cloudformation/retool.yaml) file, and add your license key and other relevant variables.
1. Go to the AWS Cloudformation dashboard, and click **Create Stack with new resources → Upload a template file**. Upload your edited `retool.yaml` file.
1. Then, enter the following parameters:
   - Cluster: the name of the ECS cluster you created earlier
   - DesiredCount: 2
   - Environment: staging
   - Force: false
   - Image: `tryretool/backend:X.Y.Z` (But replace `X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.)
   - MaximumPercent: 250
   - MinimumPercent: 50
   - SubnetId: Select 2 subnets in your VPC - make sure these subnets are public (have an internet gateway in their route table)
   - VPC ID: select the VPC you want to use
1. Click through to create the stack; this could take up to 15 minutes; you can monitor the progress of the stack being created in the `Events` tab in Cloudformation
1. After everything is complete, you should see all the resources with a `CREATE_COMPLETE` status.
1. In the **Outputs** section within the CloudFormation dashboard, you should be able to find the ALB DNS URL. This is where Retool should be running.
1. The backend tries to guess your domain to create invite links, but with a load balancer in front of Retool you'll need to set the `BASE_DOMAIN` environment variable to your fully qualified domain (i.e. `https://retool.company.com`). Docs [here](https://docs.retool.com/docs/environment-variables).

#### OOM issues

If running into OOM issues (especially on larger instance sizes with >4 vCPUs)

- Verify the issue by going into the ECS console and checking the Service Metrics. Ideally
  - Memory utilization should fall around 40% (20% - 60%)
  - CPU utilization should be close to zero (0% - 5%)
- If the values fall outside these ranges, increase the CPU and memory allocation in `retool.yml`

### Deploying on ECS with Fargate

We provide Fargate template files supporting [public](/cloudformation/fargate.yaml) and [private](/cloudformation/fargate.private.yaml) subnets.

1. In the ECS Dashboard, click **Create Cluster**
1. In **Step 1: Select a cluster template**, select `Networking Only (Powered by AWS Fargate)` as the cluster template.
1. In **Step 2: Configure cluster**, be sure to enable CloudWatch Container Insights. This will help us monitor logs and the health of our deployment through CloudWatch.
1. Download the [public](/cloudformation/fargate.yaml) or [private](/cloudformation/fargate.private.yaml) template file.
1. Edit the template file to provide your license key and any required [environment variables](https://docs.retool.com/docs/environment-variables) (under the Environment key within the retool ContainerDefinitions). Do not modify the Parameters object on line 2 of the template file. CloudFormation will prompt for these values after you upload the template file.
1. Go to the AWS CloudFormation dashboard, and click **Create Stack with new resources → Upload a template file**. Upload your edited `.yaml` file.
1. Enter the following parameters:
   - Cluster: the name of the ECS cluster you created earlier
   - DesiredCount: 2
   - Environment: staging
   - Force: false
   - Image: `tryretool/backend:X.Y.Z` (But replace `X.Y.Z` with your desired version. See [Select a Retool version number](#select-a-retool-version-number) to help you choose a version.)
   - MaximumPercent: 250
   - MinimumPercent: 50
   - SubnetId: Select 2 subnets in your VPC - make sure these subnets are public (have an internet gateway in their route table)
   - VPC ID: select the VPC you want to use
1. Click through to create the stack; this could take up to 15 minutes; you can monitor the progress of the stack being created in the `Events` tab in Cloudformation
1. In the **Outputs** section, you should be able to find the ALB DNS URL.
1. Currently the load balancer is listening on port 3000; to make it available on port 80 we have to go to the **EC2 dashboard → Load Balancers → Listeners** and click Edit to to change the port to 80.
   - If you get an error that your security group does not allow traffic on this listener port, you must add an inbound rule allowing HTTP on port 80.
1. In the **Outputs** section within the CloudFormation dashboard, you should be able to find the ALB DNS URL. This is where Retool should be running.
1. The backend tries to guess your domain to create invite links, but with a load balancer in front of Retool you'll need to set the `BASE_DOMAIN` environment variable to your fully qualified domain (i.e. `https://retool.company.com`). Docs [here](https://docs.retool.com/docs/environment-variables).

### Google Cloud Platform - Managed Deployments


## Additional Resources

**For details on additional features like SAML SSO, gRPC, custom certs, and more, visit our [docs](https://docs.retool.com/docs).**

### Environment Variables

You can set environment variables to enable custom functionality like [managing secrets](https://docs.retool.com/docs/secret-management-using-environment-variables), customizing logs, and much more. For a list of all environment variables visit our [docs](https://docs.retool.com/docs/environment-variables).

### Health check endpoint

Retool also has a health check endpoint that you can set up to monitor liveliness of Retool. You can configure your probe to make a `GET` request to `/api/checkHealth`.

### Troubleshooting

- On Kubernetes, I get the error `SequelizeConnectionError: password authentication failed for user "..."`
  - Make sure that the secrets that you encoded in base64 don't have trailing whitespace! You can use `kubectl exec printenv` to help debug this issue.
  - Run `echo -n <license key> | base64` in the command line. The `-n` character removes the trailing newline character from the encoding.
- I can't seem to login? I keep getting redirected to the login page after signing in.
  - If you have not enabled SSL yet, you will need to add the line `COOKIE_INSECURE=true` to your `docker.env` file / environment configuration so that the authentication cookies can be sent over http. Make sure to run `sudo docker-compose up -d` after modifying the `docker.env` file.
- `TypeError: Cannot read property 'licenseVerification' of null` or `TypeError: Cannot read property 'name' of null`
  - There is an issue with your license key. Double check that the license key is correct and that it has no trailing whitespaces.
- I want to use a private IP of the machine, not the default public one
    - When you run `./install.sh`, instead of just clicking enter, type in your private IP. If you want to change this after it has already been set, modify the DOMAINS variable in the docker.env file.


### Updating Retool

The latest Retool releases can be pulled from Docker Hub. When you run an on-premise instance of Retool, you’ll need to pull an updated image in order to get new features and fixes.

See more information on our different release channels and recommended update strategies in [our documentation](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions).

### Docker Compose deployments

Update the version number in the first line of your `Dockerfile`.

```docker
FROM tryretool/backend:X.Y.Z
```

Then run the included update script `./update_retool.sh` from this directory.

### Kubernetes deployments

To update Retool on Kubernetes, you can use the following command, replacing `X.Y.Z` with the version number or named tag that you’d like to update to.

```zsh
kubectl set image deploy/api api=tryretool/backend:X.Y.Z
```

### Heroku deployments

To update a Heroku deployment that was created with the button above, you'll
need to push the desired changes to the Heroku remote.

```zsh
# This assumes you already have the `heroku` CLI installed and are logged in
heroku git:clone --app=<your-retool-app-name> # default remote name is "heroku"
git remote add upstream https://github.com/tryretool/retool-onpremise
# This will incpororate the remote changes into your _local_ copy
# Also assumes both branches are "master"
git pull upstream master
git push heroku master
```

### Deployment Health Checklist

###### Overview
We recommend completing our Deployment Health Checklist to help you improve the stability and reliability of your Retool deployment.

Please fill out the checklist and share it with our team. This information will help us better understand your infrastructure so that we can support you through product changes, proactive outreach, and more informed support.

###### Instructions
Make a copy of the [Deployment Health Checklist](https://docs.google.com/spreadsheets/d/19XYpWTnYrvsllTuM2VQGFWLiXzMHmTNAzZKyWY-sfSU) for your Retool deployment. Add your company name to the document title for reference.
Fill out the requested information on the first and second tabs.
Share your filled out with your Retool contact or support@retool.com. We will reference this in the event of any support conversations.



### Docker cheatsheet

Below is a cheatsheet for useful Docker commands. Note that you may need to prefix them with `sudo`.

| Command                                                                                         | Description                                                                                                                   |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `docker-compose up -d`                                                                          | Builds, (re)creates, starts, and attaches to containers for a service. `-d`allows containers to run in background (detached). |
| `docker-compose down`                                                                           | Stops and remove containers and networks                                                                                      |
| `docker-compose stop`                                                                           | Stops containers, but does not remove them and their networks                                                                 |
| `docker ps -a`                                                                                  | Display all Docker containers                                                                                                 |
| `docker-compose ps -a`                                                                          | Display all containers related to images declared in the `docker-compose` file.                                               |
| `docker logs -f <container_name>`                                                               | Stream container logs to stdout                                                                                               |
| `docker exec -it <container_name> psql -U <postgres_user> -W <postgres_password> <postgres_db>` | Runs `psql` inside a container                                                                                                |
| `docker kill $(docker ps -q)`                                                                   | Kills all running containers                                                                                                  |
| `docker rm $(docker ps -a -q)`                                                                  | Removes all containers and networks                                                                                           |
| `docker rmi -f $(docker images -q)`                                                             | Removes (and un-tags) all images from the host                                                                                |
| `docker volume rm $(docker volume ls -q)`                                                       | Removes all volumes and completely wipes any persisted data                                                                   |
