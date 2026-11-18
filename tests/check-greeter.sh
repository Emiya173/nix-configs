#!/usr/bin/env bash
# Run each host's configured greetd command against a software-only output.
set -euo pipefail
export HOME="$TMPDIR/home"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export NOCTALIA_GREETER_STATE_DIR="$TMPDIR/state"
mkdir -m 700 "$HOME" "$XDG_RUNTIME_DIR" "$NOCTALIA_GREETER_STATE_DIR"
unset WAYLAND_DISPLAY WAYLAND_SOCKET GREETD_SOCK DISPLAY
export NOCTALIA_GREETER_LOG=stderr WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1
export WLR_RENDERER=pixman LIBGL_ALWAYS_SOFTWARE=1
export LIBGL_DRIVERS_PATH="$MESA_DIR/lib/dri"
export __EGL_VENDOR_LIBRARY_FILENAMES="$MESA_DIR/share/glvnd/egl_vendor.d/50_mesa.json"
for command in "$WORKSTATION_GREETER" "$PERSONAL_GREETER"; do
  status=0
  timeout -k 3s 12s dbus-run-session --config-file="$DBUS_SESSION_CONF" -- \
    bash -c "exec $command" >"$TMPDIR/greeter.log" 2>&1 || status=$?
  if [[ $status != 124 ]] || ! grep -Eq 'greeter initialized \([1-9][0-9]* view\(s\)\)' "$TMPDIR/greeter.log"; then
    cat "$TMPDIR/greeter.log"
    exit 1
  fi
done
