# syntax = docker/dockerfile:experimental
ARG IMG
FROM ${IMG}

ARG IMG
ENV BASE_IMAGE=${IMG}

RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/cache/yum,sharing=locked \
    dnf update -y

ENV DEPS="\
    coreutils-single \
    glibc-minimal-langpack \
    openssl \
    openssl-devel \
    zlib-devel \
    wget \
    git \
    cmake \
    ninja-build \
    gcc \
    gcc-c++ \
    perl-core \
    xz \
    libnccl-devel \
    libnccl-static \
    libstdc++-static \
    libatomic \
    "

RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/cache/yum,sharing=locked \
    dnf install -y ${DEPS} && \
    if grep -q 'release 8' /etc/redhat-release; then \
        dnf install -y gcc-toolset-13 gcc-toolset-13-gcc-c++; \
    fi

RUN wget https://github.com/ccache/ccache/releases/download/v4.14.2/ccache-4.14.2-linux-x86_64-glibc.tar.xz
RUN tar -xJf ccache-4.14.2-linux-x86_64-glibc.tar.xz \
    -C /usr/local/bin/ \
    --strip-components=1 \
    --no-same-owner \
    --no-same-permissions \
    && rm ccache-4.14.2-linux-x86_64-glibc.tar.xz \
    && mkdir -p /usr/local/bin/ccache_stubs \
    && ln -s /usr/local/bin/ccache /usr/local/bin/ccache_stubs/nvcc \
    && ln -s /usr/local/bin/ccache /usr/local/bin/ccache_stubs/gcc \
    && ln -s /usr/local/bin/ccache /usr/local/bin/ccache_stubs/g++ \
    && ln -s /usr/local/bin/ccache /usr/local/bin/ccache_stubs/cc \
    && ln -s /usr/local/bin/ccache /usr/local/bin/ccache_stubs/c++

ENV OPENSSL_ROOT_DIR="/usr/local/ssl"
ENV PATH="/usr/local/bin/ccache_stubs:/opt/rh/gcc-toolset-13/root/usr/bin:${PATH}"

RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

RUN wget https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz && \
    tar -xzf zlib-1.3.1.tar.gz && \
    cd zlib-1.3.1 && \
    ./configure --static && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf zlib-1.3.1 zlib-1.3.1.tar.gz

RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.3.1/openssl-3.3.1.tar.gz && \
    tar -xzf openssl-3.3.1.tar.gz && \
    cd openssl-3.3.1 && \
    ./config no-shared --prefix=/usr/local/ssl --openssldir=/etc/pki/tls && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf openssl-3.3.1 openssl-3.3.1.tar.gz

RUN wget https://nodejs.org/dist/v26.9.0/node-v26.9.0-linux-x64.tar.xz && \
    tar -xf node-v26.9.0-linux-x64.tar.xz -C /usr/local --strip-components=1 && \
    rm node-v26.9.0-linux-x64.tar.xz

RUN git config --global --add safe.directory '*'

WORKDIR /work
