#!/bin/bash
# Headless self-test: stability matrix + persistence + backward-compat.
# Exercises every wallpaper path, checks for crashes, rebuild-loops, and persistence.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

APP="$HOME/Library/Caches/LucidWallpaperBuild/Build/Products/Debug/LucidWallpaper.app/Contents/MacOS/LucidWallpaper"
SUPPORT="$HOME/Library/Application Support/LucidWallpaper"
LIB="$SUPPORT/library.json"
PASS=0; FAIL=0

# Ensure test assets exist.
[ -f /tmp/portrait.mp4 ] || swift scripts/make-test-video.swift /tmp/portrait.mp4 480 854 >/dev/null
[ -d /tmp/test-lively ] || { echo "missing /tmp/test-lively"; exit 1; }

wait_marker() { # file, marker
  for _ in $(seq 1 80); do
    grep -q "$2" "$1" 2>/dev/null && return 0
    for _ in $(seq 1 30000); do :; done
  done
  return 1
}

run_case() { # name, marker, env...
  local name="$1" marker="$2"; shift 2
  local log="/tmp/selftest_${name}.log"
  killall LucidWallpaper 2>/dev/null; sleep 0.3; rm -f "$log"
  env "$@" "$APP" > "$log" 2>&1 &
  local pid=$!
  local ok=0; wait_marker "$log" "$marker" && ok=1
  local alive=no; kill -0 "$pid" 2>/dev/null && alive=yes
  local crash; crash=$(grep -icE "fatal error|uncaught exception|signal SIG|Crashed:|EXC_BAD" "$log")
  local windows; windows=$(grep -c "window screen=" "$log")
  killall LucidWallpaper 2>/dev/null
  if [ "$ok" = 1 ] && [ "$alive" = yes ] && [ "$crash" = 0 ] && [ "$windows" -le 3 ]; then
    echo "PASS  $name (windows=$windows)"; PASS=$((PASS+1))
  else
    echo "FAIL  $name (marker=$ok alive=$alive crash=$crash windows=$windows) -> $log"; FAIL=$((FAIL+1))
  fi
}

check() { # description, condition(0=pass)
  if [ "$2" = 0 ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1"; FAIL=$((FAIL+1)); fi
}

echo "=== Stability matrix ==="
run_case "test-gradient"  "renderer=TestPatternRenderer" LUCIDWALL_AUTOSTART=test
run_case "web-sample"     "renderer=WebRenderer"         LUCIDWALL_AUTOSTART=sample
run_case "video-fill"     "gravity=AVLayerVideoGravityResizeAspectFill" LUCIDWALL_AUTOSTART=/tmp/portrait.mp4 LUCIDWALL_VIDEO_SCALE=fill
run_case "video-fit"      "gravity=AVLayerVideoGravityResizeAspect zoom" LUCIDWALL_AUTOSTART=/tmp/portrait.mp4 LUCIDWALL_VIDEO_SCALE=fit
run_case "video-stretch"  "gravity=AVLayerVideoGravityResize zoom"       LUCIDWALL_AUTOSTART=/tmp/portrait.mp4 LUCIDWALL_VIDEO_SCALE=stretch

echo "=== Persistence ==="
rm -rf "$SUPPORT"
killall LucidWallpaper 2>/dev/null; sleep 0.3
env LUCIDWALL_AUTOSTART=lively:/tmp/test-lively "$APP" >/tmp/p_lively.log 2>&1 &
wait_marker /tmp/p_lively.log "imported Lively"; for _ in $(seq 1 40000); do :; done; killall LucidWallpaper 2>/dev/null
python3 - "$LIB" <<'PY'; check "lively item persisted (title/kind/currentID/props)" $?
import json,sys
d=json.load(open(sys.argv[1]))
assert len(d["items"])==1, d
it=d["items"][0]
assert it["kind"]=="web" and it["title"]=="Test Lively Web", it
assert d["currentItemID"]==it["id"], d
assert it.get("propertiesURL"), it
PY

rm -rf "$SUPPORT"
killall LucidWallpaper 2>/dev/null; sleep 0.3
env LUCIDWALL_AUTOSTART=addvideo:/tmp/portrait.mp4 LUCIDWALL_VIDEO_SCALE=fit LUCIDWALL_VIDEO_ZOOM=1.5 "$APP" >/tmp/p_vid.log 2>&1 &
wait_marker /tmp/p_vid.log "added video"; for _ in $(seq 1 40000); do :; done; killall LucidWallpaper 2>/dev/null
python3 - "$LIB" <<'PY'; check "videoScaling persisted (mode=fit zoom=1.5)" $?
import json,sys
d=json.load(open(sys.argv[1]))
vs=d.get("videoScalings") or {}
assert vs, d
one=list(vs.values())[0]
assert one["mode"]=="fit", one
assert abs(one["zoom"]-1.5)<0.001, one
PY

echo "=== Backward compatibility (old library.json without new fields) ==="
python3 - "$LIB" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d.pop("overrides",None); d.pop("videoScalings",None)   # simulate a v0.1 file
json.dump(d, open(sys.argv[1],"w"))
PY
killall LucidWallpaper 2>/dev/null; sleep 0.3
"$APP" >/tmp/p_compat.log 2>&1 &   # no autostart -> restoreLast()
ok=0; wait_marker /tmp/p_compat.log "renderer=VideoRenderer" && ok=1
killall LucidWallpaper 2>/dev/null
check "v0.1 library loads + restores wallpaper" $([ "$ok" = 1 ] && echo 0 || echo 1)

echo "=== Corruption safety (bad library.json must be backed up, never wiped) ==="
rm -f "$SUPPORT"/library.corrupt-*.json 2>/dev/null
printf '{ this is not valid json' > "$LIB"
killall LucidWallpaper 2>/dev/null; sleep 0.3
"$APP" >/tmp/p_corrupt.log 2>&1 &   # no autostart -> load() must not crash or wipe
cpid=$!
cok=0; wait_marker /tmp/p_corrupt.log "window screen=" && cok=1
alive=no; kill -0 "$cpid" 2>/dev/null && alive=yes
killall LucidWallpaper 2>/dev/null
backup=$(ls "$SUPPORT"/library.corrupt-*.json 2>/dev/null | head -1)
ccrash=$(grep -icE "fatal error|signal SIG|Crashed:|EXC_BAD" /tmp/p_corrupt.log)
if [ "$cok" = 1 ] && [ "$alive" = yes ] && [ "$ccrash" = 0 ] && [ -n "$backup" ]; then
  check "corrupt library backed up (not wiped), no crash" 0
else
  echo "  (came-up=$cok alive=$alive crash=$ccrash backup=${backup:-none})"
  check "corrupt library backed up (not wiped), no crash" 1
fi
# Leave a clean slate: drop the deliberately-corrupt file + backups so a real launch re-seeds.
rm -f "$LIB" "$SUPPORT"/library.corrupt-*.json 2>/dev/null

echo
echo "=== RESULT: $PASS passed, $FAIL failed ==="
exit $FAIL
