#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/build.log"

log_info() { echo -e "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_error() { echo -e "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }

trap 'log_error "Script crashed on line $LINENO"' ERR

exec > >(tee -a "${LOG_FILE}") 2>&1

log_info "Starting Llama.cpp UBI build script"

if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
else
    log_error "No .env file found in ${SCRIPT_DIR}."
    exit 1
fi

POSSIBLE_TARGETS=("package" "package_static" "package_dynamic")
if [[ ! " ${POSSIBLE_TARGETS[*]} " =~ " ${TARGET} " ]]; then
    log_error "Invalid target: ${TARGET}. Valid options are: ${POSSIBLE_TARGETS[*]}"
    exit 1
fi

LLAMA_DIR="${SCRIPT_DIR}/${LLAMA_DIR_NAME}"

cd "${SCRIPT_DIR}"

echo "====================================="
echo "GIT"
echo "====================================="
if [ ! -d "${LLAMA_DIR}" ]; then
    git clone "${LLAMA_REPO}" "${LLAMA_DIR}"
else
    cd "${LLAMA_DIR}"
    git pull || true
    cd "${SCRIPT_DIR}"
fi

echo "====================================="
echo "DOCKER BUILD"
echo "====================================="
{
    echo -e "${FULL_PREPEND}"
    cat "${SCRIPT_DIR}/${DOCKERFILE_BASE}"
} > "${SCRIPT_DIR}/${DOCKERFILE_UBI}"

docker buildx build \
    -t "${OUT_IMG}:${LABEL}" \
    -f "${SCRIPT_DIR}/${DOCKERFILE_UBI}" \
    --build-arg CUDA="${CUDA}" \
    --build-arg FLAVOR="${FLAVOR}" \
    --build-arg OS="${OS}" \
    "${SCRIPT_DIR}"

echo "================================="
echo "MAKE"
echo "================================="
MAKE_COMMAND="\
    make -f /work/${MAKEFILE} ${TARGET:-package} \
    "

docker run --rm -it \
    -v "${SCRIPT_DIR}:/work:Z" \
    -v "${LLAMA_DIR}:/work/${LLAMA_DIR_NAME}:Z" \
    -w "/work/${LLAMA_DIR_NAME}" \
    "${OUT_IMG}:${LABEL}" \
    bash -c "${MAKE_COMMAND}"

echo "Outputs :"
echo "- ${SCRIPT_DIR}/llama-cuda86-89-static-portable.tar.gz"
echo "- ${SCRIPT_DIR}/llama-cuda86-89-dynamic-portable.tar.gz"
