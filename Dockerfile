ARG VERSION=3.383.0-edge

FROM tryretool/agent-sandbox-service:${VERSION} AS agent-sandbox

FROM tryretool/code-executor-service:${VERSION} AS code-executor

FROM tryretool/js-executor-service:${VERSION} AS js-executor

FROM tryretool/onprem:${VERSION}

CMD ./docker_scripts/start_api.sh
