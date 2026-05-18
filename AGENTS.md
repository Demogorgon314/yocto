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
- For uncommitted local one-kvm testing, a temporary `externalsrc` bbappend can point the recipe at `/workspace/one-kvm`; then `bitbake one-kvm` is enough. Do not commit that bbappend unless requested.
- Expected one-kvm IPK output:
  `build/tmp/deploy/ipk/armv8a/one-kvm_git-r0_armv8a.ipk`
- For fast binary-only one-kvm validation from the external source tree, build with:
  ```sh
  docker run --rm \
    -v /home/wangkai/github/yocto:/workspace \
    -w /workspace \
    -e LOCAL_UID=1000 \
    -e LOCAL_GID=1000 \
    streambox-builder \
    /bin/bash -lc 'source meta-meson/aml-setenv.sh mesont7c-kvim4-5.15 >/tmp/aml-setenv.log && bitbake one-kvm'
  ```
- Fast binary output path:
  `build/tmp/work/armv8a-poky-linux/one-kvm/git-r0/packages-split/one-kvm/usr/bin/one-kvm`

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
- The same board may also appear on the upstream Wi-Fi as `192.168.50.156`; Moonlight mDNS may prefer that address.
- SSH user/password: `root` / `Streamb0x`
- Quick install:
  ```sh
  sshpass -p Streamb0x scp -o StrictHostKeyChecking=no build/tmp/deploy/ipk/armv8a/one-kvm_git-r0_armv8a.ipk root@192.168.172.1:/tmp/one-kvm_git-r0_armv8a.ipk
  sshpass -p Streamb0x ssh -o StrictHostKeyChecking=no root@192.168.172.1 'opkg install --force-reinstall /tmp/one-kvm_git-r0_armv8a.ipk && systemctl daemon-reload && systemctl restart one-kvm'
  ```
- Fast binary-only install for testing:
  ```sh
  sshpass -p Streamb0x scp -o StrictHostKeyChecking=no build/tmp/work/armv8a-poky-linux/one-kvm/git-r0/packages-split/one-kvm/usr/bin/one-kvm root@192.168.172.1:/tmp/one-kvm.new
  sshpass -p Streamb0x ssh -o StrictHostKeyChecking=no root@192.168.172.1 'set -e; systemctl stop one-kvm || true; cp /usr/bin/one-kvm /usr/bin/one-kvm.bak.$(date +%s) 2>/dev/null || true; install -m 0755 /tmp/one-kvm.new /usr/bin/one-kvm; systemctl start one-kvm; sleep 3; systemctl is-active one-kvm'
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
- VIM4 HDMI capture should use the Amlogic VFM/VML path through `libvfmcap`, not direct generic V4L2 frame handling. `/dev/video_cap` may report the current kernel format as `AMLY` (`Amlogic YUV 4:2:2 10-bit packed`), but the working One-KVM path opens vfmcap with `VfmcapOutputFmt::Nv12` or `P010` and feeds DMA-buf frames directly to the Amlogic encoder.
- A healthy SDR path logs `AML pipeline: capture opened 1920x1080 @ 60fps img_format=Nv12`, then `first frame ... fmt=0x3231564e` (`NV12`) and continuing `encoded frame` messages.
- If HDMI source changes and the log shows repeated `vfmcap_acquire_frame failed (rc=-5): Vulkan render failed: vkCreateImage failed: -1000158000`, treat it as a stale vfmcap/Vulkan import state. The AML pipeline should stop and rebuild instead of waiting forever for a reconfigured frame.
- After a bad vfmcap state during development, a `systemctl restart one-kvm.service` can recover once HDMI RX is stable. Check `journalctl -u streambox-tv.service` for `[HEADLESS] Stable signal detected` and `/sys/class/hdmirx/hdmirx0/info` for the actual input mode.

## Sunshine / Moonlight Notes
- Reference implementation source is `/home/wangkai/github/Sunshine`.
- One-KVM source for the compatibility layer is `/home/wangkai/github/yocto/one-kvm/src/sunshine.rs`.
- Moonlight/GameStream is not plain RTSP. It needs NVHTTP discovery/control, PIN pairing, client certificate storage/verification, launch session creation, encrypted RTSP support, encrypted control/input, and RTP media transport.
- Current One-KVM Sunshine work implements NVHTTP HTTP/HTTPS, mDNS `_nvstream._tcp.local`, `/serverinfo`, PIN pairing, `/applist`, `/launch`, `/resume`, `/cancel`, and paired-client state under `/etc/one-kvm/sunshine`.
- Current GameStream prototype also implements RTSP on TCP 48010, video RTP over UDP 47998, ENet control/input over UDP 47999 using `libs/rusty_enet`, and exposes one app named `HDMI Input`.
- Do not edit `build/tmp/work/.../one-kvm/...` directly. Make Moonlight/Sunshine changes in `/home/wangkai/github/yocto/one-kvm`, then rebuild with Docker/BitBake.
- `Cargo.toml` currently uses a local `rusty_enet` path dependency: `libs/rusty_enet`.
- `/serverinfo` must return `PairStatus=0` unless the Moonlight `uniqueid` is present in the saved paired-client list. Returning `1` just because a `uniqueid` query parameter exists makes Moonlight skip PIN pairing incorrectly.
- `/applist` should expose a real app, currently `HDMI Input` with `ID=1` and `SupportedSOPS` entries including 3840x2160@60 and 1920x1080@120.
- If the One-KVM settings page does not show the Moonlight/Sunshine pairing UI after a binary-only update, hard-refresh the browser. `index.html` should be served with `Cache-Control: no-cache`; hashed assets may keep long cache.
- PIN can also be submitted without the One-KVM web UI through Sunshine's compatibility endpoint: `http://192.168.172.1:47989/pin?pin=1234`.
- Use `journalctl -fu one-kvm` on the board and filter for `Moonlight|GameStream|ENet` to watch `/serverinfo`, `/pair`, `/applist`, `/launch`, RTSP setup, UDP port learning, first keyframe send, and disconnect reason.
- Moonlight video transport currently sends H.265 GameStream RTP without real FEC. Intermittent black screens are likely startup keyframe packet loss or client-port race issues. The current mitigation learns the real video client port from Moonlight's UDP ping, starts on a keyframe, requests extra startup keyframes, and paces large frames in small packet batches.
- Reuse the existing One-KVM video/audio/HID pipelines where possible. Avoid vendoring or running the full Sunshine C++ daemon unless we explicitly decide to package it as a separate sidecar.
