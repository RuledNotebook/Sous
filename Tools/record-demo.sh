#!/bin/zsh
# Record a CookAlong demo: the simulator on the right, your webcam on the left.
#
# NOTE: while Device Hub is showing the iPhone Duo, `simctl io recordVideo` gets no frames from it.
# For the Duo, record with OBS instead (Sources: macOS Screen Capture > Application > Device Hub,
# plus Video Capture Device > FaceTime HD Camera). This script works for ordinary simulators.
#
#   Tools/record-demo.sh [--duo "Sous Hinge Duo"] [--link <youtube url> | --demo] [--seconds 90]
#                        [--camera "FaceTime HD Camera"] [--mic "MacBook Pro Microphone"]
#
# The simulator is recorded with `simctl io recordVideo` (clean device video, no permissions needed).
# The webcam and microphone are recorded with ffmpeg (brew install ffmpeg); the first run asks for
# camera and microphone access for your terminal. Both clips start together and are joined into a
# 1920x1080 demo-<time>.mp4: webcam in the left 720 px, the Duo fitted into the right 1200 px.
# List device names with: ffmpeg -f avfoundation -list_devices true -i ""
# Stop early with Ctrl-C; the clips are still joined.
set -euo pipefail

DUO_NAME="Sous Hinge Duo"; LINK=""; DEMO=0; SECONDS_TO_RECORD=90; CAMERA="FaceTime HD Camera"; MIC="MacBook Pro Microphone"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --duo) DUO_NAME="$2"; shift 2 ;;
    --link) LINK="$2"; shift 2 ;;
    --demo) DEMO=1; shift ;;
    --seconds) SECONDS_TO_RECORD="$2"; shift 2 ;;
    --camera) CAMERA="$2"; shift 2 ;;
    --mic) MIC="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done

BUNDLE=com.cookalong.CookAlong
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys; d=json.load(sys.stdin); name='$DUO_NAME'
for rt,devs in d['devices'].items():
    for x in devs:
        if x['name']==name: print(x['udid']); sys.exit()
sys.exit(1)") || { echo "No simulator called '$DUO_NAME'. Pick one: "; xcrun simctl list devices | grep -i duo; exit 1; }

OUT_DIR="${DEMO_OUT:-$HOME/Desktop/CookAlong demos}"; mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
DEVICE_CLIP="$OUT_DIR/device-$STAMP.mp4"; CAM_CLIP="$OUT_DIR/webcam-$STAMP.mp4"; FINAL="$OUT_DIR/demo-$STAMP.mp4"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
if [[ -n "$LINK" ]]; then
  xcrun simctl launch "$UDID" "$BUNDLE" -autoLink "$LINK" >/dev/null
elif [[ $DEMO = 1 ]]; then
  xcrun simctl launch "$UDID" "$BUNDLE" -autoDemo YES >/dev/null
else
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
fi
echo "App running on $DUO_NAME. Recording ${SECONDS_TO_RECORD}s (Ctrl-C to stop early)…"

HAVE_FFMPEG=0; command -v ffmpeg >/dev/null && HAVE_FFMPEG=1
CAM_PID=""
if [[ $HAVE_FFMPEG = 1 ]]; then
  # Start the camera first: it takes a few seconds to deliver its first frame. The device recording
  # starts once the webcam file is growing, so both clips begin at the same moment.
  ffmpeg -hide_banner -loglevel error -y -f avfoundation -framerate 30 -video_size 1280x720 -pixel_format nv12 \
    -i "$CAMERA:$MIC" -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k "$CAM_CLIP" &
  CAM_PID=$!
  for i in $(seq 1 60); do
    [[ -f "$CAM_CLIP" && $(stat -f%z "$CAM_CLIP" 2>/dev/null || echo 0) -gt 50000 ]] && break
    kill -0 $CAM_PID 2>/dev/null || { echo "Webcam recording failed (check camera/microphone access for this terminal)."; CAM_PID=""; break; }
    sleep 0.25
  done
else
  echo "ffmpeg not found (brew install ffmpeg): recording the device only."
fi

xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$DEVICE_CLIP" 2>/dev/null &
DEVICE_PID=$!

stop() { kill -INT $DEVICE_PID 2>/dev/null || true; [[ -n "$CAM_PID" ]] && kill -INT $CAM_PID 2>/dev/null || true; }
trap 'stop' INT TERM
( sleep "$SECONDS_TO_RECORD"; stop ) &
SLEEPER=$!
wait $DEVICE_PID 2>/dev/null || true
[[ -n "$CAM_PID" ]] && wait $CAM_PID 2>/dev/null || true
kill $SLEEPER 2>/dev/null || true
sleep 1

if [[ $HAVE_FFMPEG = 1 && -s "$CAM_CLIP" ]]; then
  # 1920x1080: webcam cropped to the left 720 px, the Duo fitted (any pose) into the right 1200 px.
  ffmpeg -hide_banner -loglevel error -y -i "$CAM_CLIP" -i "$DEVICE_CLIP" \
    -filter_complex "[0:v]scale=-2:1080,crop=720:1080,setsar=1[cam];[1:v]scale=w=1200:h=1080:force_original_aspect_ratio=decrease,pad=1200:1080:(ow-iw)/2:(oh-ih)/2:color=0x141414,setsar=1[dev];[cam][dev]hstack=inputs=2[v]" \
    -map "[v]" -map "0:a?" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -movflags +faststart "$FINAL"
  echo "Done: $FINAL"
else
  echo "Device clip: $DEVICE_CLIP"
fi
