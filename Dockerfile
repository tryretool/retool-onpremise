ARG VERSION=dev-3.380.0-940f7d8

FROM --platform=linux/amd64 753800337063.dkr.ecr.us-west-2.amazonaws.com/agent-executor-service:${VERSION} AS agent-sandbox

FROM --platform=linux/amd64 753800337063.dkr.ecr.us-west-2.amazonaws.com/code-executor-service:${VERSION} AS code-executor

FROM --platform=linux/amd64 753800337063.dkr.ecr.us-west-2.amazonaws.com/onprem:${VERSION}

CMD ./docker_scripts/start_api.sh
