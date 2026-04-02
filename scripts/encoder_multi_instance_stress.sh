#!/usr/bin/env bash

set -euo pipefail

TARGET="${TARGET:-root@192.168.12.156}"
ITERATIONS="${ITERATIONS:-20}"
MIN_SLEEP="${MIN_SLEEP:-1}"
MAX_SLEEP="${MAX_SLEEP:-4}"

REMOTE_STATE_DIR="/tmp/encoder_multi_instance_stress"
HDMI_PID_FILE="$REMOTE_STATE_DIR/hdmi.pid"
UVC_PID_FILE="$REMOTE_STATE_DIR/uvc.pid"
HDMI_LOG_FILE="$REMOTE_STATE_DIR/hdmi.log"
UVC_LOG_FILE="$REMOTE_STATE_DIR/uvc.log"

HDMI_CMD="gst-launch-1.0 -e streamboxsrc source=vfmcap output-format=p010 num-buffers=-1 ! \"video/x-raw,format=P010_10LE,width=3840,height=2160\" ! queue max-size-buffers=5 max-size-time=0 max-size-bytes=0 ! amlvenc internal-bit-depth=10 gop=60 gop-pattern=0 bitrate=30000 framerate=60 ! video/x-h265 ! h265parse config-interval=-1 ! queue max-size-buffers=30 max-size-time=0 max-size-bytes=0 ! mpegtsmux alignment=7 latency=100000000 ! srtsink uri=\"srt://:8888\" wait-for-connection=false sync=false"
UVC_CMD="gst-launch-1.0 -e v4l2src device=/dev/video0 num-buffers=-1 ! \"video/x-h264,width=1920,height=1080,framerate=30/1\" ! h264parse ! amlv4l2h264dec ! queue max-size-buffers=5 max-size-time=0 max-size-bytes=0 ! \"video/x-raw,format=NV12\" ! amlvenc bitrate=4000 framerate=30 gop=5 gop-pattern=0 ! video/x-h265 ! h265parse config-interval=-1 ! queue max-size-buffers=30 max-size-time=0 max-size-bytes=0 ! mpegtsmux alignment=7 latency=100000000 ! srtsink uri=\"srt://:8889\" wait-for-connection=false sync=false"

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

remote() {
    ssh "$TARGET" "$@"
}

remote_sh() {
    printf '%s\n' "$1" | ssh "$TARGET" sh -s
}

remote_init() {
    remote_sh "mkdir -p $REMOTE_STATE_DIR"
}

remote_cleanup_all() {
    remote_sh "if [ -f $HDMI_PID_FILE ]; then kill \
        \$(cat $HDMI_PID_FILE) 2>/dev/null || true; rm -f $HDMI_PID_FILE; fi; \
        if [ -f $UVC_PID_FILE ]; then kill \$(cat $UVC_PID_FILE) 2>/dev/null || true; \
        rm -f $UVC_PID_FILE; fi; \
        pkill -f 'gst-launch-1.0 -e streamboxsrc source=vfmcap' 2>/dev/null || true; \
        pkill -f 'gst-launch-1.0 -e v4l2src device=/dev/video0' 2>/dev/null || true"
}

start_pipeline() {
    local name="$1"
    local pid_file="$2"
    local log_file="$3"
    local cmd="$4"
    remote_sh "mkdir -p $REMOTE_STATE_DIR; \
        if [ -f $pid_file ] && kill -0 \$(cat $pid_file) 2>/dev/null; then \
        cat $pid_file; exit 0; fi; \
        $cmd > $log_file 2>&1 & echo \$! > $pid_file; cat $pid_file"
}

stop_pipeline() {
    local pid_file="$1"
    remote_sh "if [ -f $pid_file ]; then kill \$(cat $pid_file) 2>/dev/null || true; \
        sleep 1; kill -9 \$(cat $pid_file) 2>/dev/null || true; rm -f $pid_file; fi"
}

is_running() {
    local pid_file="$1"
    remote_sh "if [ -f $pid_file ] && kill -0 \$(cat $pid_file) 2>/dev/null; then echo yes; else echo no; fi"
}

show_logs() {
    log "HDMI log tail"
    remote "sed -n '1,120p' '$HDMI_LOG_FILE' 2>/dev/null || true"
    log "UVC log tail"
    remote "sed -n '1,120p' '$UVC_LOG_FILE' 2>/dev/null || true"
}

assert_expected_state() {
    local expect_hdmi="$1"
    local expect_uvc="$2"
    local hdmi_state
    local uvc_state
    hdmi_state="$(is_running "$HDMI_PID_FILE")"
    uvc_state="$(is_running "$UVC_PID_FILE")"

    if [[ "$expect_hdmi" == "yes" && "$hdmi_state" != "yes" ]]; then
        log "ERROR: HDMI pipeline died unexpectedly"
        show_logs
        exit 1
    fi

    if [[ "$expect_uvc" == "yes" && "$uvc_state" != "yes" ]]; then
        log "ERROR: UVC pipeline died unexpectedly"
        show_logs
        exit 1
    fi
}

assert_peer_unchanged() {
    local action="$1"
    local hdmi_before="$2"
    local uvc_before="$3"

    case "$action" in
        restart_hdmi|stop_hdmi|start_hdmi)
            if [[ "$uvc_before" == "yes" ]]; then
                assert_expected_state no yes
            fi
            ;;
        restart_uvc|stop_uvc|start_uvc)
            if [[ "$hdmi_before" == "yes" ]]; then
                assert_expected_state yes no
            fi
            ;;
    esac
}

sleep_random() {
    local span=$((MAX_SLEEP - MIN_SLEEP + 1))
    local delay=$((MIN_SLEEP + RANDOM % span))
    sleep "$delay"
}

main() {
    local i action hdmi_running uvc_running

    remote_init
    remote_cleanup_all

    log "Starting both pipelines"
    log "HDMI pid: $(start_pipeline hdmi "$HDMI_PID_FILE" "$HDMI_LOG_FILE" "$HDMI_CMD")"
    sleep 2
    log "UVC pid: $(start_pipeline uvc "$UVC_PID_FILE" "$UVC_LOG_FILE" "$UVC_CMD")"
    sleep 2
    assert_expected_state yes yes

    for ((i = 1; i <= ITERATIONS; i++)); do
        hdmi_running="$(is_running "$HDMI_PID_FILE")"
        uvc_running="$(is_running "$UVC_PID_FILE")"

        case $((RANDOM % 6)) in
            0) action="restart_hdmi" ;;
            1) action="restart_uvc" ;;
            2) action="stop_hdmi" ;;
            3) action="stop_uvc" ;;
            4) action="start_hdmi" ;;
            *) action="start_uvc" ;;
        esac

        log "Iteration $i/$ITERATIONS action=$action hdmi=$hdmi_running uvc=$uvc_running"

        case "$action" in
            restart_hdmi)
                if [[ "$hdmi_running" == "yes" ]]; then
                    stop_pipeline "$HDMI_PID_FILE"
                fi
                start_pipeline hdmi "$HDMI_PID_FILE" "$HDMI_LOG_FILE" "$HDMI_CMD" >/dev/null
                ;;
            restart_uvc)
                if [[ "$uvc_running" == "yes" ]]; then
                    stop_pipeline "$UVC_PID_FILE"
                fi
                start_pipeline uvc "$UVC_PID_FILE" "$UVC_LOG_FILE" "$UVC_CMD" >/dev/null
                ;;
            stop_hdmi)
                if [[ "$hdmi_running" == "yes" ]]; then
                    stop_pipeline "$HDMI_PID_FILE"
                fi
                ;;
            stop_uvc)
                if [[ "$uvc_running" == "yes" ]]; then
                    stop_pipeline "$UVC_PID_FILE"
                fi
                ;;
            start_hdmi)
                if [[ "$hdmi_running" != "yes" ]]; then
                    start_pipeline hdmi "$HDMI_PID_FILE" "$HDMI_LOG_FILE" "$HDMI_CMD" >/dev/null
                fi
                ;;
            start_uvc)
                if [[ "$uvc_running" != "yes" ]]; then
                    start_pipeline uvc "$UVC_PID_FILE" "$UVC_LOG_FILE" "$UVC_CMD" >/dev/null
                fi
                ;;
        esac

        sleep_random
        assert_peer_unchanged "$action" "$hdmi_running" "$uvc_running"

        if [[ "$(is_running "$HDMI_PID_FILE")" == "no" && "$(is_running "$UVC_PID_FILE")" == "no" ]]; then
            log "Both pipelines stopped; restarting both to keep stress meaningful"
            log "HDMI pid: $(start_pipeline hdmi "$HDMI_PID_FILE" "$HDMI_LOG_FILE" "$HDMI_CMD")"
            sleep 1
            log "UVC pid: $(start_pipeline uvc "$UVC_PID_FILE" "$UVC_LOG_FILE" "$UVC_CMD")"
            sleep 2
            assert_expected_state yes yes
        fi
    done

    log "Stress run completed successfully"
    remote_cleanup_all
}

main "$@"
