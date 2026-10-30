#!/bin/bash
# Runs a compiled game with no device and saves screenshots.
# Usage: test/run-game.sh <dir with Game and libpxt.so> <output dir> [Game args...]
# Set OLD_GLIBC=1 to run on glibc 2.28, which is older than the device's 2.30.
# Set KEYS to a list of xdotool keys to press after the first screenshot.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
shift 2

IMAGE=makecode-test
DOCKERFILE="$HERE/Dockerfile"
if [ -n "$OLD_GLIBC" ]; then
  IMAGE=makecode-test-old
  DOCKERFILE="$HERE/Dockerfile.old-glibc"
fi
docker build -q --platform linux/arm64 -t "$IMAGE" -f "$DOCKERFILE" "$HERE" > /dev/null

docker run --rm --platform linux/arm64 --network none \
  -v "$GAME":/game:ro -v "$OUT":/out \
  -e SDL_AUDIODRIVER=dummy -e KEYS="$KEYS" "$IMAGE" bash -c '
    # The game saves settings in its folder, so it runs from a writable copy
    cp -r /game /run/game && cd /run/game
    ldd --version | head -1
    Xvfb :9 -screen 0 640x480x24 > /dev/null 2>&1 &
    export DISPLAY=:9
    until xdotool getdisplaygeometry > /dev/null 2>&1; do sleep 0.2; done
    ./Game "$@" > /out/run.log 2>&1 &
    P=$!
    sleep 3; import -window root /out/a.png
    for k in $KEYS; do xdotool keydown $k; sleep 0.2; xdotool keyup $k; sleep 0.2; done
    sleep 3; import -window root /out/b.png
    sleep 3; import -window root /out/c.png
    if kill -0 $P 2> /dev/null; then echo "alive after 9s"; kill $P; else wait $P; echo "exited: $?"; fi
    tail -5 /out/run.log
  ' _ "$@"
