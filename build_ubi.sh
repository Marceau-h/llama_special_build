#!/usr/bin/env bash
set -euao pipefail

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

TARGET="${1:-${TARGET}}"

# Parse TARGET profile
if [[ "$TARGET" == default_* ]]; then
    OS="ubi8"
    ARCHS="86;89"
    GGML_NATIVE="OFF"
    CPU_FLAGS=""
    PKG_PREFIX="llama-default"
    MAKE_TARGET="${TARGET#default_}"
elif [[ "$TARGET" == full_* ]]; then
    OS="ubi8"
    ARCHS="75;80;86;89;90"
    GGML_NATIVE="OFF"
    CPU_FLAGS=""
    PKG_PREFIX="llama-full"
    MAKE_TARGET="${TARGET#full_}"
elif [[ "$TARGET" == tailored_* ]]; then
    OS="ubi8"
    ARCHS="86;89"
    GGML_NATIVE="OFF"
    CPU_FLAGS="-march=znver3"
    PKG_PREFIX="llama-tailored"
    MAKE_TARGET="${TARGET#tailored_}"
else
    log_error "Invalid target: ${TARGET}. Valid prefixes: default_, full_, tailored_ (followed by static, dynamic, or package)"
    exit 1
fi

PKG_STATIC="${PKG_PREFIX}-static.tar.zst"
PKG_DYNAMIC="${PKG_PREFIX}-dynamic.tar.zst"

if [[ "$MAKE_TARGET" == "package" ]]; then
    REAL_TARGET="package"
else
    REAL_TARGET="package_${MAKE_TARGET}"
fi

LABEL="${CUDA}-${FLAVOR}-${OS}"
LLAMA_DIR="${SCRIPT_DIR}/${LLAMA_DIR_NAME}"

echo "====================================="
echo "Configuration"
echo "====================================="
echo "TARGET: ${TARGET}"
echo "MAKE_TARGET: ${MAKE_TARGET}"
echo "REAL_TARGET: ${REAL_TARGET}"

echo "OS: ${OS}"
echo "ARCHS: ${ARCHS}"
echo "CPU_FLAGS: ${CPU_FLAGS}"

echo "DOCKER_IMAGE_NAME: ${DOCKER_IMAGE_NAME}"
echo "LABEL: ${LABEL}"

env > "${SCRIPT_DIR}/build_full_env.log"
echo "See full configuration in ${SCRIPT_DIR}/build_full_env.log"

set +a

cd "${SCRIPT_DIR}"

echo "====================================="
echo "GIT"
echo "====================================="
if [ ! -d "${LLAMA_DIR}" ]; then
    git clone "${LLAMA_REPO}" "${LLAMA_DIR}"
fi

git -C "${LLAMA_DIR}" reset --hard HEAD
git -C "${LLAMA_DIR}" fetch --all --tags

LLAMA_REF="${LLAMA_REF:-master}"

if [ "${LLAMA_REF}" = "master" ]; then
    git -C "${LLAMA_DIR}" checkout -B master origin/master
elif [ "${LLAMA_REF}" = "latest_tag" ]; then
    LATEST_TAG="$(git -C "${LLAMA_DIR}" describe --tags --abbrev=0 origin/master)"
    git -C "${LLAMA_DIR}" checkout "${LATEST_TAG}"
else
    git -C "${LLAMA_DIR}" checkout "${LLAMA_REF}"
fi

git -C "${LLAMA_DIR}" apply "${SCRIPT_DIR}/ca_probe.patch"

echo "================================="
echo "MAKE"
echo "================================="
BUILD_DIR="${BUILD_DIR:-build}"
BUILD_BASE="/work/${BUILD_DIR}"
NPROC="$(nproc 2>/dev/null || echo 1)"
DEFAULT_JOBS="$(( NPROC > 1 ? NPROC - 1 : 1 ))"
JOBS="${JOBS:-$DEFAULT_JOBS}"

MAKE_COMMAND="\
    export CC=gcc CXX=g++ && \
    make -f /work/${MAKEFILE} clean && \
    make -f /work/${MAKEFILE} -j${JOBS} ${REAL_TARGET} && \
    make -f /work/${MAKEFILE} clean_post
    "

docker run --rm -it --network=host \
    --entrypoint bash \
    -e NVIDIA_VISIBLE_DEVICES=none \
    -e CCACHE_DIR="${BUILD_BASE}/ccache" \
    -e UI_CACHE_DIR="${BUILD_BASE}/ui_cache" \
    -e JOBS="${JOBS:-}" \
    -e ARCHS="${ARCHS}" \
    -e GGML_NATIVE="${GGML_NATIVE}" \
    -e CPU_FLAGS="${CPU_FLAGS}" \
    -e PKG_STATIC="${PKG_STATIC}" \
    -e PKG_DYNAMIC="${PKG_DYNAMIC}" \
    -e BUILD_STATIC="${BUILD_BASE}/build_static_${PKG_PREFIX}" \
    -e BUILD_DYNAMIC="${BUILD_BASE}/build_dynamic_${PKG_PREFIX}" \
    -e DIST_STATIC="${BUILD_BASE}/dist_static_${PKG_PREFIX}" \
    -e DIST_DYNAMIC="${BUILD_BASE}/dist_dynamic_${PKG_PREFIX}" \
    -v "${SCRIPT_DIR}:/work:Z" \
    -v "${LLAMA_DIR}:/work/${LLAMA_DIR_NAME}:Z" \
    -w "/work/${LLAMA_DIR_NAME}" \
    "${DOCKER_USER}/${OUT_IMG}:${LABEL}" \
    -c "${MAKE_COMMAND}"

echo "Outputs :"
echo "- ${SCRIPT_DIR}/${PKG_STATIC}"
echo "- ${SCRIPT_DIR}/${PKG_DYNAMIC}"