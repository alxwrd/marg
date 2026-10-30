#!/bin/bash
# Runs a compiled game with no device and saves screenshots.
# Usage: test/run-game.sh <dir with Game and libpxt.so> <output dir> [--palette-fix] [Game args...]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
shift 2
PRELOAD=""
if [ "$1" = "--palette-fix" ]; then
  PRELOAD=/fix/libpalette_fix.so
  shift
fi

docker build -q --platform linux/arm64 -t makecode-test "$HERE" > /dev/null

docker run --rm --platform linux/arm64 --network none \
  -v "$HERE/../reference":/src:ro -v "$GAME":/game:ro -v "$OUT":/out -w /game \
  -e SDL_AUDIODRIVER=dummy -e PRELOAD="$PRELOAD" makecode-test bash -c '
    if [ -n "$PRELOAD" ]; then
      mkdir /fix && gcc -shared -fPIC -O2 -o /fix/libpalette_fix.so /src/palette_fix.c
    fi
    Xvfb :9 -screen 0 640x480x24 > /dev/null 2>&1 &
    sleep 1
    export DISPLAY=:9
    LD_PRELOAD=$PRELOAD ./Game "$@" > /out/run.log 2>&1 &
    P=$!
    sleep 3; import -window root /out/a.png
    sleep 3; import -window root /out/b.png
    if kill -0 $P 2> /dev/null; then echo "alive after 6s"; kill $P; else wait $P; echo "exited: $?"; fi
    tail -5 /out/run.log
  ' _ "$@"
