<p align="center">
    <a href="https://tryretool.com/"><img src="http://tryretool.com/logo.png" alt="Retool logo" height="100"></a> <br><br>
<b>Retool lets you build custom internal tools in minutes.</b></p>






# Repository for deploying Retool on-premise

Retool can be setup on premise in around 15 minutes. You should use either Docker, Kubernetes, or Heroku. If you're not sure what to use, use Docker.

## Getting started

### Quick and simple start.

1. Run `./install.sh`to install Docker and Docker Compose
1. Run `sudo docker-compose up` to start the Retool server

### Running Retool using Docker

1. Install `docker` and `docker-compose`
    1. Provided are two convenience scripts for making it easy to install docker and docker-compose: `./get-docker.sh` and `./get-docker-compose.sh`
2. Run `./docker_setup` and use the default values provided
    1. If you do not have bash, you can adapt the docker.env.template file
3. Run `sudo docker-compose up` to start the Retool server
4. Be sure to open up port 80 and port 443 on the virtual machine's host
5. Navigate to your server's ip address in a web browser to get started.

#### Updating Retool using docker-compose

1. Run `./update_retool.sh`
1. Alternatively, stop the server, and run `sudo docker-compose pull` and then `sudo docker-compose up -d`

### Running Retool on Kubernetes with Helm

1. A helm chart is included in this repository under the ./helm directory
2. The available parameters are documented using comments in the ./helm/values.yaml file

```
helm install ./helm
```

3. Persistent volumes are not reliable - we recommend that a long-term installation of Retool host the database on an externally managed database like RDS. Please disable the included `postgresql` chart by setting `postgresql.enabled` to `false` and then specifying your external database through the `config.postgresql.*` properties.

### Running Retool on Kubernetes

1. Navigate into the `kubernetes` directory
2. Copy the `retool-secrets.template.yaml` file to `retool-secrets.yaml` and inside the `{{ ... }}` sections, replace with a suitable base64 encoded string.
    1. If you do not wish to add google authentication, replace the templates with an empty string.
    1. You will need a license key in order to proceed.
3. Run `kubectl apply -f ./retool-secrets.yaml`
4. Run `kubectl apply -f ./retool-postgres.yaml`
4. Run `kubectl apply -f ./retool-container.yaml`

For ease of use, this will create a postgres container with a persistent volume for the storage of Retool data. We recommend that you use a managed database service like RDS as a long-term solution. The application will be exposed on a public ip address on port 3000 - we leave it to the user to handle DNS and SSL.

Please note that by default Retool is configured to use Secure Cookies - that means that you will be unable to login unless https has been correctly setup.

To force Retool to send the auth cookies over HTTP, please set the `COOKIE_INSECURE` environment variable to `'true'` in `./retool-container.yaml`. Do this by adding the following two lines to the `env` section.

```
        - name: COOKIE_INSECURE
          value: 'true'
```

Then, to update the running deployment, run `$ kubectl apply -f ./retool-container.yaml`

#### Updating Retool on Kubernetes
To update Retool on Kubernetes, you can use the following command:

```
$ kubectl set image deploy/api api=tryretool/backend:X.XX.X

```

The list of available version numbers for X.XX.X are available here: https://updates.tryretool.com/

### Deploying to Heroku

Just use the Deploy to Heroku button below!

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

#### Updating a Heroku deployment

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

#### Manually setting up Retool on Heroku

Alternatively, you may follow the following steps to deploy to Heroku

1. Install the Heroku CLI, and login. Documentation for this can be found here: https://devcenter.heroku.com/articles/getting-started-with-nodejs#set-up
1. Clone this repo `git clone https://github.com/tryretool/retool-onpremise`
1. Change the working directory to the newly cloned repository `cd ./retool-onpremise`
1. Create a new Heroku app with the stack set to `container` with `heroku create your-app-name --stack=container`
1. Add a free database: `heroku addons:create heroku-postgresql:hobby-dev`
1. In the `Settings` page of your Heroku app, add the following environment variables:
    1. `NODE_ENV` - set to `production`
    1. `HEROKU_HOSTED` set to `true`
    1. `JWT_SECRET`  - set to a long secure random string used to sign JSON Web Tokens
    1. `ENCRYPTION_KEY` - a long secure random string used to encrypt database credentials

1. Push the code: `git push heroku master`

To lockdown the version of Retool used, just edit the first line under `./heroku/Dockerfile` to:
```
FROM tryretool/backend:X.XX.X
```

### Deploying to Render

Just use the Deploy to Render button below!

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/render-examples/retool)

### Running Retool using Aptible

1. Add your public SSH key to your Aptible account through the Aptible dashboard
1. Install the Aptible CLI, and login. Documentation for this can be found here: https://www.aptible.com/documentation/deploy/cli.html
1. Clone this repo `git clone https://github.com/tryretool/retool-onpremise`
1. Change the working directory to the newly cloned repository `cd ./retool-onpremise`
1. Create a new Aptible app with `aptible apps:create your-app-name`
1. Add a database: `aptible db:create your-database-name --type postgresql`
1. Set your config variables (your database connection string will be in your Aptible Dashboard and you can parse out the individual values by following these instructions: https://www.aptible.com/documentation/deploy/reference/databases/credentials.html#using-database-credentials):
    ```
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

## Health check endpoint 

Retool also has a health check endpoint that you can set up to monitor liveliness of Retool. You can configure your probe to make a `GET` request to `/api/checkHealth`.

## Adding Google Login

Create a Google oauth client using the tutorial below:

https://developers.google.com/identity/sign-in/web/devconsole-project

The Oauth Client screen should end up looking something like this:
![Sample Google Oauth Config Screen](https://i.imgur.com/yOoYGQd.png)

Add the following to your `docker.env` file

```
CLIENT_ID={YOUR_GOOGLE_CLIENT_ID}
CLIENT_SECRET={YOUR_GOOGLE_CLIENT_SECRET}
RESTRICTED_DOMAIN=yourcompany.com
```

Restart the server and you will have Google login for your org!

In Kubernetes, instead of editing the `docker.env` file, place the base64 encoded version of these strings inside the kubernetes secrets file

## Integrating with SAML (e.g. Okta)

Retool also supports SAML authentication schemes. Below is a guide to integrating Retool with Okta.

1. Login into Okta as an admin. Make sure to use the Classic UI.
1. Navigate to the `Applications` section of Okta
1. Create a new application using the SAML wizard. More information can be found here: https://help.okta.com/en/prod/Content/Topics/Apps/Apps_App_Integration_Wizard.htm
1. When presented with the `Create a New Appication Integration` dialog, choose:
    1. Platform: `Web`
    1. Sign on method: `SAML 2.0`
1. You will then be directed to a 3 step wizard.
    1. For the first step (General Settings) , name the application 'Retool', and then press next.
    1. For the second step (Configure SAML):
        1. Single sign on URL: https://retool.yourcompany.com/saml/login
        1. Audience URI: retool.yourcompany.com
        1. Attribute Statements: Retool requires three attributes to be present:
            1. firstName: user.firstName
            1. lastName: user.lastName
            1. email: user.email
        1. Leave everything else as default. See below for an example of a valid configuration.
          ![Sample Okta SAML Configuration](https://i.imgur.com/K7VQSiBg.png)
    1. For the third step 
        1. Check 'I'm an Okta customer adding an internal app"
        1. Check "This is an internal app that we have created"
        1. Click 'Finish'
1. The last step will be to provide the Retool instance with the Identity Provider metadata. To do this, press the 'View Setup Instructions' button. A new page with IDP metadata will appear. Copy the XML at the bottom of the page, and then:
    1. If you are using the `docker-compose` setup, add the following line to your `docker.env` file. The XML content will contain multiple lines, so make sure to remove all line endings so that the entire XML string is one line in the `docker.env file`
        ```
        SAML_IDP_METADATA=<?xml version="1.0" encoding="UTF-8"?>...</md:EntityDescriptor>
        ```
    1. If you are using Heroku to deploy Retool, add a new environment variable called `SAML_IDP_METADATA` with the value of the XML document. No further steps are required.

## Disabling password-based sign-in

To disable the use of email + password sign-in, define the `RESTRICTED_DOMAIN` environment variable. For example, using the `docker.env` file, use this:
```
RESTRICTED_DOMAIN=yourcompany.com
```

Note that, if you are using this in conjuction with Google login, Retool will compare the value supplied to `RESTRICTED_DOMAIN` with the domain of users that attempt to authenticate with Google SSO and reject accounts from different domains.

## Troubleshooting:

- On Kubernetes, I get the error `SequelizeConnectionError: password authentication failed for user "..."`
    - Make sure that the secrets that you encoded in base64 don't have trailing whitespace! You can use `kubectl exec printenv` to help debug this issue.
- I can't seem to login?
    - If you have not enabled SSL yet, you will need to add the line `COOKIE_INSECURE=true` to your `docker.env` file / environment configuration so that the authentication cookies can be sent over http.

