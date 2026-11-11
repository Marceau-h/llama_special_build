#!/usr/bin/env bash
set -euao pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/build_docker.log"

log_info() { echo -e "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_error() { echo -e "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }

trap 'log_error "Script crashed on line $LINENO"' ERR

exec > >(tee -a "${LOG_FILE}") 2>&1

if [ -f "${SCRIPT_DIR}/.env" ]; then
    source "${SCRIPT_DIR}/.env"
else
    log_error "No .env file found in ${SCRIPT_DIR}."
    exit 1
fi

LOCAL_DOCKERFILE_HASH=$(sha256sum "${SCRIPT_DIR}/${DOCKERFILE_BASE}" | awk '{print $1}')

set +a

if ! docker buildx version > /dev/null 2>&1; then
    log_error "docker buildx not found."
    exit 1
fi

CACHE_ARGS=()

if [ "${NO_CACHE:-false}" != "true" ]; then
    CACHE_ARGS+=(
        --cache-from "${GHCR_IMAGE_NAME}"
        --cache-from "${DOCKER_IMAGE_NAME}"
        --cache-to type=inline
    )
fi

docker buildx build \
    --load \
    -t "${DOCKER_IMAGE_NAME}" \
    -t "${GHCR_IMAGE_NAME}" \
    -f "${SCRIPT_DIR}/${DOCKERFILE_BASE}" \
    --build-arg IMG="${IMG}" \
    "${CACHE_ARGS[@]}" \
    --label "DOCKERFILE_HASH=${LOCAL_DOCKERFILE_HASH}" \
    "${SCRIPT_DIR}"

log_info "Built Docker image: ${DOCKER_IMAGE_NAME}"
