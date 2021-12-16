<p align="center">
    <a href="https://retool.com/"><img src="https://raw.githubusercontent.com/tryretool/brand-assets/master/Logos/logo-full-black.png" alt="Retool logo" height="100"></a> <br>
    <b>Build internal tools, remarkably fast.</b>
</p> <br>

# Deploying Retool on-premise

Deploying Retool on-premise ensures that all access to internal data is managed within your own cloud environment. You also have the flexibility to control how Retool is setup within your infrastructure, configure logging, and enable custom SAML SSO using providers like Okta and Active Directory.

# Table of contents

- [Select a Retool version number](#select-a-retool-version-number)
- [Simple deployments](#simple-deployments)
  - [EC2 and Docker](#deploying-on-ec2)
  - [AWS](#deploying-to-aws-using-opta)
  - [Heroku](#deploying-on-heroku)
  - [Aptible](#running-retool-using-aptible)
  - [Render](#deploying-to-render)
- [Managed deployments](#managed-deployments)
  - [ECS](#deploying-on-ecs)
  - [ECS + Fargate](#deploying-on-ecs-with-fargate)
  - [Kubernetes](#deploying-on-kubernetes)
  - [Kubernetes + Helm](#deploying-on-kubernetes-with-helm)
- [Additional features](#additional-features)
  - [Health check endpoint](#health-check-endpoint)
  - [Environment variables](#environment-variables)
- [Troubleshooting](#troubleshooting)
- [Updating Retool](#updating-retool)
- [Releases](#releases)
- [Docker cheatsheet](#docker-cheatsheet)

## Select a Retool version number

We recommend you set your Retool deployment to a specific version of Retool (that is, a specific semver version number in the format `X.Y.Z`, instead of a tag name). This will help prevent unexpected behavior in your Retool instances. When you are ready to upgrade Retool, you can bump the version number to the specific new version you want.

To help you select a version, see our guide on [Retool Release Versions](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions).

## Simple Deployments

Get set up in 15 minutes by deploying Retool on a single machine.

### Deploying on Heroku

Just use the Deploy to Heroku button below! You'll then have to go to Settings and set the `LICENSE_KEY` to your license key and `PGSSLMODE` to `require`.

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

### Manually setting up Retool on Heroku

Alternatively, you may follow the following steps to deploy to Heroku

1. Install the Heroku CLI, and login. Documentation for this can be found here: https://devcenter.heroku.com/articles/getting-started-with-nodejs#set-up
1. Clone this repo `git clone https://github.com/tryretool/retool-onpremise`
1. Change the working directory to the newly cloned repository `cd ./retool-onpremise`
1. Create a new Heroku app with the stack set to `container` with `heroku create your-app-name --stack=container`
1. Add a free database: `heroku addons:create heroku-postgresql:hobby-dev`
1. In the `Settings` page of your Heroku app, add the following environment variables:
   1. `NODE_ENV` - set to `production`
   1. `HEROKU_HOSTED` set to `true`
   1. `JWT_SECRET` - set to a long secure random string used to sign JSON Web Tokens
   1. `ENCRYPTION_KEY` - a long secure random string used to encrypt database credentials
   1. `LICENSE_KEY` - your Retool license key
   1. `PGSSLMODE` - set to `require`
1. Push the code: `git push heroku master`

To lockdown the version of Retool used, just edit the first line under `./heroku/Dockerfile` to:

```
FROM tryretool/backend:X.Y.Z
```

### Environment Variables

You can set environment variables to enable custom functionality like [managing secrets](https://docs.retool.com/docs/secret-management-using-environment-variables), customizing logs, and much more. For a list of all environment variables visit our [docs](https://docs.retool.com/docs/environment-variables).

### Health check endpoint

Retool also has a health check endpoint that you can set up to monitor liveliness of Retool. You can configure your probe to make a `GET` request to `/api/checkHealth`.

## Troubleshooting

- On Kubernetes, I get the error `SequelizeConnectionError: password authentication failed for user "..."`
  - Make sure that the secrets that you encoded in base64 don't have trailing whitespace! You can use `kubectl exec printenv` to help debug this issue.
  - Run `echo -n <license key> | base64` in the command line. The `-n` character removes the trailing newline character from the encoding.
- I can't seem to login? I keep getting redirected to the login page after signing in.
  - If you have not enabled SSL yet, you will need to add the line `COOKIE_INSECURE=true` to your `docker.env` file / environment configuration so that the authentication cookies can be sent over http. Make sure to run `sudo docker-compose up -d` after modifying the `docker.env` file.
- `TypeError: Cannot read property 'licenseVerification' of null` or `TypeError: Cannot read property 'name' of null`
  - There is an issue with your license key. Double check that the license key is correct and that it has no trailing whitespaces.

## Updating Retool

The latest Retool releases can be pulled from Docker Hub. When you run an on-premise instance of Retool, you’ll need to pull an updated image in order to get new features and fixes.

See more information on our different release channels and recommended update strategies in [our documentation](https://docs.retool.com/docs/updating-retool-on-premise#retool-release-versions).

### Heroku deployments

To update a Heroku deployment that was created with the button above, you may first set up a `git` repo to push to Heroku

```
$ heroku login
$ git clone https://github.com/tryretool/retool-onpremise
$ cd retool-onpremise
$ heroku git:remote -a YOUR_HEROKU_APP_NAME
```

To update Retool (this will automatically fetch the latest version of Retool)

```
$ git commit --allow-empty -m 'Redeploying'
$ git push heroku master
```

## Releases

Releases notes can be found at [https://updates.retool.com](https://updates.retool.com/en).

## Docker cheatsheet

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
