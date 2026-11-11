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

OUTPUT_ARGS=()
if [ "${PUSH:-false}" = "true" ] || [ "${PUSH_IMAGE:-false}" = "true" ] || [[ "${1:-}" == "--push" ]]; then
    OUTPUT_ARGS=(--push)
fi

TAG_ARGS=(-t "${GHCR_IMAGE_NAME}")
if [ "${#OUTPUT_ARGS[@]}" -eq 0 ] || [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    TAG_ARGS+=(-t "${DOCKER_IMAGE_NAME}")
fi

docker buildx build \
    "${OUTPUT_ARGS[@]}" \
    "${TAG_ARGS[@]}" \
    -f "${SCRIPT_DIR}/${DOCKERFILE_BASE}" \
    --build-arg IMG="${IMG}" \
    "${CACHE_ARGS[@]}" \
    --label "DOCKERFILE_HASH=${LOCAL_DOCKERFILE_HASH}" \
    "${SCRIPT_DIR}"

log_info "Built Docker image: ${DOCKER_IMAGE_NAME}"
