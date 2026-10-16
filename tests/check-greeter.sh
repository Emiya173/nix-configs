#!/usr/bin/env bash
# Exercise the real launcher in a private Wayland display, without a login or VT.
set -euo pipefail
: "${GREETER_LAUNCHER:?}"
: "${PLAIN_QUICKSHELL:?}"
: "${DBUS_SESSION_CONF:?}"
: "${MESA_DIR:?}"

export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_STATE_HOME="$TMPDIR/state"
mkdir -m 700 "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
mkdir -m 700 "$TMPDIR/greeter"
export LIBGL_ALWAYS_SOFTWARE=1
export LIBGL_DRIVERS_PATH="$MESA_DIR/lib/dri"
export __EGL_VENDOR_LIBRARY_FILENAMES="$MESA_DIR/share/glvnd/egl_vendor.d/50_mesa.json"
export QT_QUICK_BACKEND=software

weston --backend=headless --renderer=pixman --socket=greeter-test --idle-time=0 \
  --width=1024 --height=768 > "$TMPDIR/weston.log" 2>&1 &
weston_pid=$!
trap 'kill "$weston_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  [[ -S "$XDG_RUNTIME_DIR/greeter-test" ]] && break
  kill -0 "$weston_pid" || { cat "$TMPDIR/weston.log"; exit 1; }
  sleep 0.1
done
[[ -S "$XDG_RUNTIME_DIR/greeter-test" ]]
export WAYLAND_DISPLAY=greeter-test
# Reproduce the system-wide qs that shadowed the greeter's Qt wrapper.
export PATH="$PLAIN_QUICKSHELL/bin:$PATH"
export NIRI_CONFIG="$TMPDIR/not-the-greeter.kdl"
set +e
timeout 15s dbus-run-session --config-file="$DBUS_SESSION_CONF" -- \
  "$GREETER_LAUNCHER" --cache-dir "$TMPDIR/greeter" --debug \
  > "$TMPDIR/greeter.log" 2>&1
status=$?
set -e
# Niri detaches spawned clients' stdout; Quickshell keeps its own binary log.
for log in "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.qslog; do
  [[ -f "$log" ]] || continue
  "$PLAIN_QUICKSHELL/bin/qs" log --no-color "$log" >> "$TMPDIR/greeter.log" 2>&1
done
if [[ $status != 124 ]] || ! grep -q 'Configuration Loaded' "$TMPDIR/greeter.log"; then
  cat "$TMPDIR/greeter.log"
  exit 1
fi
if grep -q 'Failed to load configuration' "$TMPDIR/greeter.log"; then
  cat "$TMPDIR/greeter.log"
  exit 1
fi
