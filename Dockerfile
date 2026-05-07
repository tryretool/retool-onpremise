# Check Dockerhub for available tags: https://hub.docker.com/r/tryretool/backend/tags

ARG VERSION=X.Y.Z-stable

FROM tryretool/agent-sandbox-service:${VERSION} AS agent-sandbox

FROM tryretool/code-executor-service:${VERSION} AS code-executor

FROM tryretool/js-executor-service:${VERSION} AS js-executor

FROM tryretool/backend:${VERSION}

CMD ./docker_scripts/start_api.sh
