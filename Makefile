SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := package
.PHONY: build_static build_dynamic package_static package_dynamic package clean clean_post

# Include environment variables
-include $(dir $(abspath $(lastword $(MAKEFILE_LIST)))).env

ARCHS ?= 86;89
GGML_NATIVE ?= OFF
CPU_FLAGS ?= 
PKG_STATIC ?= llama-static-portable.tar.zst
PKG_DYNAMIC ?= llama-dynamic-portable.tar.zst
BUILD_DIR ?= build
BUILD_BASE := $(if $(filter /%,$(BUILD_DIR)),$(BUILD_DIR),/work/$(BUILD_DIR))
BUILD_STATIC ?= $(BUILD_BASE)/build_static
DIST_STATIC ?= $(BUILD_BASE)/dist_static
BUILD_DYNAMIC ?= $(BUILD_BASE)/build_dynamic
DIST_DYNAMIC ?= $(BUILD_BASE)/dist_dynamic
UI_CACHE_DIR ?= $(BUILD_BASE)/ui_cache

restore_ui_cache:
	@mkdir -p $(UI_CACHE_DIR)
	@UI_HASH=$$(git -C /work/llama.cpp rev-parse HEAD:tools/ui 2>/dev/null || echo "none") ; \
	if [ -n "$$UI_HASH" ] && [ "$$UI_HASH" != "none" ]; then \
		flock $(UI_CACHE_DIR)/.lock bash -c " \
			if [ -f '$(UI_CACHE_DIR)/'\"$$UI_HASH\"'/index.html' ]; then \
				mkdir -p /work/llama.cpp/tools/ui/dist && \
				cp -a '$(UI_CACHE_DIR)/'\"$$UI_HASH\"'/'* /work/llama.cpp/tools/ui/dist/ && \
				echo '--- Restored UI from cache ($$UI_HASH) ---' ; \
			fi \
		" ; \
	fi

build_static:
	@echo "--- Configuring llama.cpp (Static) ---"
	mkdir -p $(BUILD_STATIC)
	cmake -B $(BUILD_STATIC) -S . -G Ninja \
		-DGGML_CUDA=ON \
		-DCMAKE_CUDA_ARCHITECTURES="$(subst ",,$(ARCHS))" \
		-DGGML_NATIVE=$(GGML_NATIVE) \
		-DCMAKE_C_FLAGS="$(CPU_FLAGS)" \
		-DCMAKE_CXX_FLAGS="$(CPU_FLAGS)" \
		-DGGML_VULKAN=OFF \
		-DGGML_STATIC=ON \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_BUILD_TYPE=Release \
		-DGGML_BUILD_EXAMPLES=OFF \
		-DLLAMA_BUILD_EXAMPLES=OFF \
		-DLLAMA_BUILD_TESTS=OFF \
		-DLLAMA_BUILD_SERVER=ON \
		-DLLAMA_BUILD_UI=ON \
		-DLLAMA_USE_PREBUILT_UI=OFF \
		-DOPENSSL_USE_STATIC_LIBS=ON \
		-DNCCL_LIBRARY=/usr/lib64/libnccl_static.a \
		-DCMAKE_CXX_STANDARD_LIBRARIES="-lstdc++fs -L/usr/local/cuda/lib64 -lcudart_static -lcudadevrt -lrt -lpthread -ldl" \
		-DCMAKE_EXE_LINKER_FLAGS="-static-libgcc -static-libstdc++ -fuse-ld=lld" \
		-DCMAKE_CUDA_FLAGS="--compiler-options -static-libgcc"
	@echo "--- Building llama.cpp (Static) ---"
	cmake --build $(BUILD_STATIC) -j$$(($$(nproc) - 1))
	cmake --build $(BUILD_STATIC) --target llama-cli llama-server -j$$(($$(nproc) - 1))

build_dynamic:
	@echo "--- Configuring llama.cpp (Dynamic) ---"
	mkdir -p $(BUILD_DYNAMIC)
	cmake -B $(BUILD_DYNAMIC) -S . -G Ninja \
		-DGGML_CUDA=ON \
		-DCMAKE_CUDA_ARCHITECTURES="$(subst ",,$(ARCHS))" \
		-DGGML_NATIVE=$(GGML_NATIVE) \
		-DCMAKE_C_FLAGS="$(CPU_FLAGS)" \
		-DCMAKE_CXX_FLAGS="$(CPU_FLAGS)" \
		-DGGML_VULKAN=OFF \
		-DGGML_STATIC=OFF \
		-DBUILD_SHARED_LIBS=ON \
		-DCMAKE_BUILD_TYPE=Release \
		-DGGML_BUILD_EXAMPLES=OFF \
		-DLLAMA_BUILD_EXAMPLES=OFF \
		-DLLAMA_BUILD_TESTS=OFF \
		-DLLAMA_BUILD_SERVER=ON \
		-DLLAMA_BUILD_UI=ON \
		-DLLAMA_USE_PREBUILT_UI=OFF \
		-DOPENSSL_USE_STATIC_LIBS=ON \
		-DCMAKE_CXX_STANDARD_LIBRARIES="-lstdc++fs -ldl" \
		-DCMAKE_INSTALL_RPATH='$$ORIGIN:$$ORIGIN/../lib' \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
		-DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link=/usr/local/cuda/lib64/stubs" \
		-DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link=/usr/local/cuda/lib64/stubs"
	@echo "--- Building llama.cpp (Dynamic) ---"
	cmake --build $(BUILD_DYNAMIC) -j$$(($$(nproc) - 1))
	cmake --build $(BUILD_DYNAMIC) --target llama-cli llama-server -j$$(($$(nproc) - 1))

package_static: build_static
	@echo "--- Packaging (Static) ---"
	rm -rf $(DIST_STATIC)
	mkdir -p $(DIST_STATIC)

	cp -a $(BUILD_STATIC)/bin/llama-cli $(DIST_STATIC)/
	cp -a $(BUILD_STATIC)/bin/llama-server $(DIST_STATIC)/

	tar -C $(DIST_STATIC) -I 'zstd -T8' -cf /work/$(PKG_STATIC) .
	@echo "--- Created $(PKG_STATIC) ---"

package_dynamic: build_dynamic
	@echo "--- Packaging (Dynamic) ---"
	rm -rf $(DIST_DYNAMIC)
	mkdir -p $(DIST_DYNAMIC)/bin $(DIST_DYNAMIC)/lib

	cp -a $(BUILD_DYNAMIC)/bin/llama-cli $(DIST_DYNAMIC)/bin/
	cp -a $(BUILD_DYNAMIC)/bin/llama-server $(DIST_DYNAMIC)/bin/

	# Collect shared libraries for the binaries
	for bin in $(BUILD_DYNAMIC)/bin/llama-cli $(BUILD_DYNAMIC)/bin/llama-server; do \
		ldd "$$bin" | awk 'NF == 4 && $$3 ~ /^\// { print $$3 }' | grep -vE '/libc\.so|/libm\.so|/libdl\.so|/libpthread\.so|/librt\.so|/ld-linux|libcuda\.so|libnvidia|/libgcc_s\.so|/libstdc\+\+\.so' | xargs -I {} cp -v {} $(DIST_DYNAMIC)/lib/ || true ; \
	done

	# Also recursively collect shared libraries for the libraries themselves (e.g. libllama.so might depend on other things)
	for lib in $(DIST_DYNAMIC)/lib/*.so*; do \
		[ -f "$$lib" ] || continue ; \
		ldd "$$lib" | awk 'NF == 4 && $$3 ~ /^\// { print $$3 }' | grep -vE '/libc\.so|/libm\.so|/libdl\.so|/libpthread\.so|/librt\.so|/ld-linux|libcuda\.so|libnvidia|/libgcc_s\.so|/libstdc\+\+\.so' | xargs -I {} cp -n {} $(DIST_DYNAMIC)/lib/ 2>/dev/null || true ; \
	done

	cp /work/run-llama-server.sh $(DIST_DYNAMIC)/bin/run-llama-server.sh
	chmod +x $(DIST_DYNAMIC)/bin/run-llama-server.sh

	tar -C $(DIST_DYNAMIC) -I 'zstd -T8' -cf /work/$(PKG_DYNAMIC) .
	@echo "--- Created $(PKG_DYNAMIC) ---"

package: package_static package_dynamic

clean:
	rm -rf $(BUILD_STATIC) $(DIST_STATIC) /work/$(PKG_STATIC) $(PKG_STATIC)
	rm -rf $(BUILD_DYNAMIC) $(DIST_DYNAMIC) /work/$(PKG_DYNAMIC) $(PKG_DYNAMIC)

clean_post:
	rm -rf $(BUILD_STATIC) $(DIST_STATIC)
	rm -rf $(BUILD_DYNAMIC) $(DIST_DYNAMIC)

