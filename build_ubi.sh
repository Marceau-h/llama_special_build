#!/usr/bin/env bash
set -euo pipefail

PREPEND="# syntax = docker/dockerfile:experimental"
CUDA=13.2.0
FLAVOR=cudnn-devel
OS=ubi8
IMG=docker.io/nvidia/cuda:${CUDA}-${FLAVOR}-${OS}

LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"

FULL_PREPEND="${PREPEND}\nFROM ${IMG}\n"

DOCKERFILE_BASE="Dockerfile.base"
DOCKERFILE_UBI="Dockerfile.ubi"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="$SCRIPT_DIR/llama.cpp"

echo $SCRIPT_DIR
cd "$SCRIPT_DIR"

echo "====================================="
echo "GIT"
echo "====================================="
if [ ! -d "$LLAMA_DIR" ]; then
    git clone "$LLAMA_REPO" "$LLAMA_DIR"
else
    cd "$LLAMA_DIR"
    git pull || true
    cd "$SCRIPT_DIR"
fi

echo "====================================="
echo "DOCKER BUILD"
echo "====================================="
{
    echo -e "$FULL_PREPEND"
    cat "$SCRIPT_DIR/$DOCKERFILE_BASE"
} > "$SCRIPT_DIR/$DOCKERFILE_UBI"

docker buildx build -t llama-ubi-builder -f Dockerfile.ubi .

echo "================================="
echo "MAKE"
echo "================================="
MAKE_COMMAND="\
    make -f /work/Makefile.ubi clean \
    && make -f /work/Makefile.ubi package_static \
    "

docker run --rm -it \
    -v "$SCRIPT_DIR:/work:Z" \
    -v "$LLAMA_DIR:/work/llama.cpp:Z" \
    -w /work/llama.cpp \
    llama-ubi-builder \
    bash -c "$MAKE_COMMAND"

echo "Outputs :"
echo "- $SCRIPT_DIR/llama-cuda86-89-static-portable.tar.gz"
echo "- $SCRIPT_DIR/llama-cuda86-89-dynamic-portable.tar.gz"
