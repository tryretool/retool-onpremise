<p align="center">
    <a href="https://retool.com/"><img src="https://raw.githubusercontent.com/tryretool/brand-assets/master/Logos/logo-full-black.png" alt="Retool logo" height="100"></a> <br>
    <b>Build internal tools, remarkably fast.</b>
</p> <br>

# Deploying Retool on-premise

To ensure a better user experience when deploying Retool, we have made important updates to the Helm deployment instructions. The deployment instructions have been migrated to [official deployment guides](https://docs.retool.com/docs/self-hosted), hosted on [docs.retool.com](https://docs.retool.com/docs/self-hosted). The new guides provide more comprehensive set of deployment instructions with the goal of improving the deployment experience for our users.

We have removed several deployment types, such as Heroku and Render, because they are no longer a good fit for production use. However, you can still access the deployment instructions in the [deprecated-onpremise](https://github.com/tryretool/deprecated-onpremise) repo. We officially support the methods below

### Single deployments
  - [AWS w/ EC2](https://docs.retool.com/docs/deploy-with-aws-ec2)
  - [GCP w/ Compute Engine VM](https://docs.retool.com/docs/deploy-with-gcp)
  - [Azure w/ Azure VM](https://docs.retool.com/docs/deploy-with-azure-vm)
### Orchestrated deployments
  - [Kubernetes](https://docs.retool.com/docs/deploy-with-kubernetes)
  - [Kubernetes + Helm](https://docs.retool.com/docs/deploy-with-helm)
  - [ECS + Fargate](https://docs.retool.com/docs/deploy-with-ecs-fargate)


For any inquiries regarding deploying Retool, please feel free to reach out to us at support@retool.com or search our [Community Forums](https://community.retool.com/) and post your question there.
