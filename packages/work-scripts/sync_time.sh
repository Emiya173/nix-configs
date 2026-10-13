
set -euo pipefail

ADB_BIN="${ADB_BIN:-adb}"

command -v "$ADB_BIN" >/dev/null 2>&1 || {
    echo "error: adb not found" >&2
    exit 1
}

# Android toybox date accepts: MMDDhhmm[[CC]YY][.ss]
TIME_NOW="$(TZ=Asia/Shanghai date '+%m%d%H%M%Y.%S')"

echo "Syncing device time to $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')"

"$ADB_BIN" wait-for-device
"$ADB_BIN" root
"$ADB_BIN" wait-for-device

"$ADB_BIN" shell settings put global auto_time 0
"$ADB_BIN" shell settings put global auto_time_zone 0
"$ADB_BIN" shell date "$TIME_NOW"
"$ADB_BIN" shell setprop persist.sys.timezone Asia/Shanghai

echo "Device time:"
"$ADB_BIN" shell "date '+%Y-%m-%dT%H:%M:%S%z'"
echo "Auto time: $($ADB_BIN shell settings get global auto_time)"
echo "Auto time zone: $($ADB_BIN shell settings get global auto_time_zone)"
echo "Timezone: $($ADB_BIN shell getprop persist.sys.timezone)"
