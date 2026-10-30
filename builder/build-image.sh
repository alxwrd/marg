#!/bin/bash
# Compiles a .png export. Runs in builder/Dockerfile.
# Usage: build-image.sh <png> <output dir>
# Writes game.pxt64, name (the project's name) and tree (C++ source for the runtime).
set -e
PROJECT=/tmp/project
node /builder/extract-png.js "$1" "$PROJECT" > /tmp/meta.json
node -p 'JSON.parse(require("fs").readFileSync("/tmp/meta.json", "utf8")).name' > "$2/name"

cd "$PROJECT"
export PXT_FORCE_LOCAL=1 PXT_NODOCKER=force PATH=/builder/stub:$PATH
node /builder/pxt.js install --hw vm > /tmp/pxt.log 2>&1 || { cat /tmp/pxt.log; exit 1; }
node /builder/pxt.js build --hw vm > /tmp/pxt.log 2>&1 || { cat /tmp/pxt.log; exit 1; }
[ -f built/binary.pxt64 ] || { cat /tmp/pxt.log; echo "pxt made no image"; exit 1; }

# The image's size is at offset 0x48. A source map follows the image, and the
# runtime rejects the file with error 1001 if that makes its length unaligned
node -e '
const fs = require("fs");
const d = fs.readFileSync("built/binary.pxt64");
fs.writeFileSync(process.argv[1], d.subarray(0, d.readUInt32LE(0x48)));
' "$2/game.pxt64"
rm -rf "$2/tree"
cp -r built/dockercross "$2/tree"
