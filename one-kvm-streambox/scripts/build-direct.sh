#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${PROJECT_ROOT}/One-KVM-StreamBox"
WEB_DIR="${SOURCE_DIR}/web"
BUILD_DIR="${PROJECT_ROOT}/build-direct"
ARTIFACT_DIR="${PROJECT_ROOT}/artifacts"
SUPPORT_DIR="${PROJECT_ROOT}/support"

SDK_ENV="/home/anshi/yocto/sbs/.sdk/toolchain/sbs-sdk-mesont7c-kvim4-5.15/environment-setup-armv8a-poky-linux"
VENC_SYSROOT="/home/anshi/yocto/build/tmp/work/armv8a-poky-linux/gst-plugin-venc-multienc/1.0-r0/recipe-sysroot"
MULTIENC_DESTDIR="/home/anshi/yocto/build/tmp/work/armv8a-poky-linux/libmultienc/1.0-r0/sysroot-destdir"
VFMCP_DESTDIR="/home/anshi/yocto/build/tmp/work/armv8a-poky-linux/libvfmcap/1.0-r0/sysroot-destdir"
NATIVE_SYSROOT="/home/anshi/yocto/sbs/.sdk/toolchain/sbs-sdk-mesont7c-kvim4-5.15/sysroots/x86_64-pokysdk-linux"

TARGET="aarch64-unknown-linux-gnu"

msg() { printf "\033[1;34m[ONE-KVM-DIRECT-BUILD]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ONE-KVM-DIRECT-BUILD]\033[0m %s\n" "$*" >&2; }

build_web() {
    if [ ! -f "${WEB_DIR}/package.json" ]; then
        error "Web package.json not found at ${WEB_DIR}"
        exit 1
    fi

    msg "Building frontend assets..."
    if [ ! -d "${WEB_DIR}/node_modules" ]; then
        npm ci --prefix "${WEB_DIR}"
    fi
    npm run --prefix "${WEB_DIR}" build
}

main() {
    msg "========================================"
    msg "One-KVM Direct Cross-Build (no Yocto recipe)"
    msg "========================================"

    # Source SDK
    msg "Sourcing SDK environment: ${SDK_ENV}"
    # shellcheck disable=SC1090
    . "${SDK_ENV}"

    # Create merged sysroot with AML libraries
    msg "Preparing merged sysroot with AML libraries..."
    MERGED_SYSROOT="${BUILD_DIR}/merged-sysroot"
    mkdir -p "${MERGED_SYSROOT}"

    # Start with the venc-multienc recipe-sysroot (has ffmpeg, vulkan, etc)
    # Copy only the symlinks/lib/include structure - avoid heavy copy
    # Instead, use it directly and overlay libmultienc/libvfmcap

    # Build web assets first
    build_web

    # CARGO_TARGET_DIR
    mkdir -p "${BUILD_DIR}/target"
    export CARGO_TARGET_DIR="${BUILD_DIR}/target"

    # Prepare stub libyuv
    LIBYUV_DIR="${BUILD_DIR}/support/lib"
    LIBYUV_PC_DIR="${BUILD_DIR}/support/lib/pkgconfig"
    mkdir -p "${LIBYUV_PC_DIR}"

    if [ ! -f "${LIBYUV_DIR}/libyuv.a" ]; then
        msg "Building libyuv stub..."
        ${CROSS_COMPILE}gcc --sysroot="${SDKTARGETSYSROOT}" -c "${SUPPORT_DIR}/libyuv_stub.c" -o "${BUILD_DIR}/support/libyuv_stub.o"
        ${CROSS_COMPILE}ar rcs "${LIBYUV_DIR}/libyuv.a" "${BUILD_DIR}/support/libyuv_stub.o"
    fi

    cat > "${LIBYUV_PC_DIR}/libyuv.pc" <<EOF
prefix=${BUILD_DIR}/support
libdir=${LIBYUV_DIR}
includedir=${BUILD_DIR}/support/include

Name: libyuv
Description: Stub libyuv for AML DMA-buf build path
Version: 0.0.0
Libs: -L${LIBYUV_DIR} -lyuv
Cflags:
EOF

    # Cargo config
    CARGO_DIR="${SOURCE_DIR}/.cargo"
    mkdir -p "${CARGO_DIR}"

    # Create a simple gcc wrapper that adds --sysroot
    WRAPPER_DIR="${BUILD_DIR}/wrapper"
    mkdir -p "${WRAPPER_DIR}"

    cat > "${WRAPPER_DIR}/target-rust-ccld" <<'WRAPPER'
#!/bin/bash
# Wrapper for Rust cross-linking: uses the Yocto SDK cross-compiler with merged sysroot
exec aarch64-poky-linux-gcc --sysroot=MERGED_SYSROOT "$@"
WRAPPER
    sed -i "s|MERGED_SYSROOT|${VENC_SYSROOT}|g" "${WRAPPER_DIR}/target-rust-ccld"
    chmod +x "${WRAPPER_DIR}/target-rust-ccld"

    # Copy libmultienc and libvfmcap into the venc sysroot (for linking)
    msg "Overlaying AML libraries onto sysroot..."
    cp -rn "${MULTIENC_DESTDIR}/usr/lib/"libvpcodec.so* "${VENC_SYSROOT}/usr/lib/" 2>/dev/null || true
    cp -rn "${MULTIENC_DESTDIR}/usr/lib/"libamvenc_api.so* "${VENC_SYSROOT}/usr/lib/" 2>/dev/null || true
    cp -rn "${MULTIENC_DESTDIR}/usr/include/"vp_multi_codec_1_0.h "${VENC_SYSROOT}/usr/include/" 2>/dev/null || true
    cp -rn "${VFMCP_DESTDIR}/usr/lib/"libvfmcap.so* "${VENC_SYSROOT}/usr/lib/" 2>/dev/null || true
    cp -rn "${VFMCP_DESTDIR}/usr/include/"vfmcap.h "${VENC_SYSROOT}/usr/include/" 2>/dev/null || true

    # Link the unversioned .so symlinks if needed
    cd "${VENC_SYSROOT}/usr/lib"
    [ ! -L libvpcodec.so ] && [ -f libvpcodec.so.1 ] && ln -sf libvpcodec.so.1 libvpcodec.so || true
    [ ! -L libamvenc_api.so ] && [ -f libamvenc_api.so.1 ] && ln -sf libamvenc_api.so.1 libamvenc_api.so || true
    [ ! -L libvfmcap.so ] && [ -f libvfmcap.so.1 ] && ln -sf libvfmcap.so.1 libvfmcap.so || true
    cd "${PROJECT_ROOT}"

    # Find libclang for bindgen
    LIBCLANG_DIR=""
    for d in "${NATIVE_SYSROOT}/usr/lib/llvm-rust/lib" /usr/lib/llvm-14/lib /usr/lib/llvm-15/lib /usr/lib/llvm-16/lib /usr/lib/llvm-17/lib /usr/lib/llvm/lib; do
        if [ -f "${d}/libclang.so" ]; then
            LIBCLANG_DIR="${d}"
            break
        fi
    done
    if [ -z "${LIBCLANG_DIR}" ]; then
        LIBCLANG_DIR=$(dirname "$(find /usr/lib -name 'libclang.so' -type f 2>/dev/null | head -1)" 2>/dev/null || true)
    fi

    msg "LIBCLANG_PATH: ${LIBCLANG_DIR:-NOT_FOUND}"

    # Create .cargo/config.toml
    cat > "${CARGO_DIR}/config.toml" <<EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "${SOURCE_DIR}/vendor"

[target.${TARGET}]
linker = "${WRAPPER_DIR}/target-rust-ccld"

[build]
target = "${TARGET}"
EOF

    # rustup: ensure target is installed
    rustup target add ${TARGET} --toolchain stable 2>/dev/null || true

    export PKG_CONFIG_SYSROOT_DIR="${VENC_SYSROOT}"
    export PKG_CONFIG_PATH="${LIBYUV_PC_DIR}:${VENC_SYSROOT}/usr/lib/pkgconfig:${VENC_SYSROOT}/usr/share/pkgconfig"
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG="pkg-config"

    export LIBCLANG_PATH="${LIBCLANG_DIR}"
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${VENC_SYSROOT} -I${VENC_SYSROOT}/usr/include -I${SDKTARGETSYSROOT}/usr/include"
    export V4L2R_VIDEODEV2_H_PATH="${VENC_SYSROOT}/usr/include/linux"
    export RUSTFLAGS="-C link-arg=-Wl,--sysroot=${VENC_SYSROOT} -L ${VENC_SYSROOT}/usr/lib -L ${SDKTARGETSYSROOT}/usr/lib -L ${BUILD_DIR}/support/lib"

    # Target-specific compiler vars (used by cc-rs for target compilation only)
    export CC_aarch64_unknown_linux_gnu="aarch64-poky-linux-gcc --sysroot=${VENC_SYSROOT}"
    export CXX_aarch64_unknown_linux_gnu="aarch64-poky-linux-g++ --sysroot=${VENC_SYSROOT}"
    export CFLAGS_aarch64_unknown_linux_gnu="--sysroot=${VENC_SYSROOT} -I${VENC_SYSROOT}/usr/include -I${SDKTARGETSYSROOT}/usr/include"
    export CXXFLAGS_aarch64_unknown_linux_gnu="--sysroot=${VENC_SYSROOT} -I${VENC_SYSROOT}/usr/include -I${SDKTARGETSYSROOT}/usr/include"
    export LDFLAGS_aarch64_unknown_linux_gnu="--sysroot=${VENC_SYSROOT}"

    # CRITICAL: unset generic CC/CXX/CFLAGS/CXXFLAGS/LDFLAGS from SDK env
    # so cc-rs uses host compiler for build scripts (libsqlite3-sys, etc.)
    # and only uses target-specific vars for cross-compilation.
    unset CC CXX CPP LD AR NM RANLIB STRIP OBJCOPY OBJDUMP READELF
    unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    unset ARCH CROSS_COMPILE CONFIGURE_FLAGS TARGET_PREFIX

    export ONE_KVM_LIBS_PATH="${VENC_SYSROOT}/usr"

    msg "Building with features: aml,hwencode"

    cd "${SOURCE_DIR}"

    set +e
    cargo +stable build --release --no-default-features --features "aml,hwencode" --target "${TARGET}" 2>&1
    local build_rc=$?
    set -e

    if [ ${build_rc} -ne 0 ]; then
        error "Build failed"
        exit 1
    fi

    local binary_path="${BUILD_DIR}/target/${TARGET}/release/one-kvm"
    if [ ! -f "${binary_path}" ]; then
        error "Binary not found at: ${binary_path}"
        exit 1
    fi

    msg "Build successful: ${binary_path}"

    mkdir -p "${ARTIFACT_DIR}"
    cp "${binary_path}" "${ARTIFACT_DIR}/one-kvm"
    aarch64-poky-linux-strip "${ARTIFACT_DIR}/one-kvm" || true

    msg "Stripped binary copied to: ${ARTIFACT_DIR}/one-kvm"
    ls -lh "${ARTIFACT_DIR}/one-kvm"

    msg "========================================"
    msg "Build complete!"
    msg "========================================"
}

main "$@"