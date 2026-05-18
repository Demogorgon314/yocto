# Codex Notes for This Yocto Workspace

## Workspace
- Root: `/home/wangkai/github/yocto`
- Target board: `mesont7c-kvim4-5.15` / VIM4
- This workspace uses submodules. Keep changes scoped to the module being worked on.
- Do not commit generated build config churn, `node_modules`, or unrelated submodule dirt.

## Build Rules
- Build Yocto inside Docker. Do not run host/WSL `bitbake` for this tree.
- Use the `streambox-builder` image and initialize the Amlogic environment with:
  `source meta-meson/aml-setenv.sh mesont7c-kvim4-5.15`
- Correct one-kvm package build command:
  ```sh
  docker run --rm \
    -v /home/wangkai/github/yocto:/workspace \
    -w /workspace \
    -e LOCAL_UID=1000 \
    -e LOCAL_GID=1000 \
    streambox-builder \
    /bin/bash -lc 'source meta-meson/aml-setenv.sh mesont7c-kvim4-5.15 >/tmp/aml-setenv.log && bitbake -c clean one-kvm && bitbake one-kvm'
  ```
- Expected one-kvm IPK output:
  `build/tmp/deploy/ipk/armv8a/one-kvm_git-r0_armv8a.ipk`

## One-KVM Development
- Local source: `/home/wangkai/github/yocto/one-kvm`
- Fork remote: `git@github.com:Demogorgon314/One-KVM-StreamBox.git`
- Current development branch: `sync-upstream-main`
- After changing frontend code:
  ```sh
  cd /home/wangkai/github/yocto/one-kvm/web
  npm ci
  npm run build
  cd /home/wangkai/github/yocto/one-kvm
  tar czf /home/wangkai/github/yocto/meta-aml-cfg/recipes-kvm/one-kvm/files/one-kvm-web-dist.tar.gz web/dist
  ```

## Yocto Layer Wiring
- Yocto layer: `/home/wangkai/github/yocto/meta-aml-cfg`
- Fork remote: `git@github.com:Demogorgon314/meta-aml-cfg.git`
- one-kvm recipe: `meta-aml-cfg/recipes-kvm/one-kvm/one-kvm_git.bb`
- When one-kvm source changes are pushed, update `SRCREV` in the recipe to the pushed one-kvm commit.
- If frontend changed, also update:
  `meta-aml-cfg/recipes-kvm/one-kvm/files/one-kvm-web-dist.tar.gz`

## Board Test / Install
- Board IP used for local testing: `192.168.172.1`
- SSH user/password: `root` / `Streamb0x`
- Quick install:
  ```sh
  sshpass -p Streamb0x scp -o StrictHostKeyChecking=no build/tmp/deploy/ipk/armv8a/one-kvm_git-r0_armv8a.ipk root@192.168.172.1:/tmp/one-kvm_git-r0_armv8a.ipk
  sshpass -p Streamb0x ssh -o StrictHostKeyChecking=no root@192.168.172.1 'opkg install --force-reinstall /tmp/one-kvm_git-r0_armv8a.ipk && systemctl daemon-reload && systemctl restart one-kvm'
  ```

## HDR / Video Notes
- Current verified one-kvm HDR/hot-switch baseline is commit `909c21c300528cddeb6af0b744e9170d6ab01caf`.
- Current H.265 Main10/HDR signaling work is one-kvm commit `2eb7a8a9411f9bbf9579e14d1ddc276514fcacb1`.
- Yocto `one-kvm_git.bb` must pin `SRCREV` to that commit or newer.
- `HDR Auto` keeps browser-compatible behavior and tone maps HDR to SDR where needed.
- `SDR Only` forces SDR output.
- `HDR Passthrough` is experimental true HDR passthrough using 10-bit P010 capture. Browser/WebRTC HDR support may still be limited by client, codec, and display.
- HDR/SDR input changes should trigger the AML video pipeline to rebuild, close stale WebRTC sessions, and force the browser to negotiate a fresh WebRTC session. Do not reconnect old sessions directly to the new pipeline; that can show one frame and then freeze.
- Some Windows HDR sources may report `bitdepth=8` while still carrying HDR EOTF/status. Treat HDMI EOTF/HDR status as authoritative for passthrough; do not require bitdepth=10 to select P010.
- For true HDR WebRTC testing, use stream mode `h265` plus `HDR Passthrough`. The H.265 session should log `main10=true`, SDP offer/answer should contain H.265, and the AML pipeline should be rebuilt as `codec=H265 img_format=P010`.
- H.265 codec switches must not reuse a running H.264 pipeline. `ensure_video_pipeline` intentionally compares the existing pipeline config against the requested codec/HDR/resolution/fps/backend and recreates it on mismatch.
