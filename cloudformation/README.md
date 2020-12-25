# Cloudformation file explained

```

Parameters:

# 'staging' --> sent to cloudwatch logs
Environment

# select 2 public subnets for the load balancer
SubnetId 

# the ECS cluster(this should have already been created)
Cluster

# the docker image (tryretool/backend:latest)
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
