#!/bin/bash
# Builds libpxt.so from the C++ tree that pxt generated, and the runner. Runs in native/Dockerfile.
# Usage: build-runtime.sh <tree> <output dir>
# Writes libpxt.so and the Game runner to the output directory.
set -e
cd "$1"

# Fixes for bugs in the upstream source, which only one compiler or 32-bit builds forgive:
# - find_src_map truncates a 64-bit pointer
# - the generator writes aspxt::RefCollection(x) for pxt::RefCollection* arguments
# - the compiler writes NumberBoxes with the 32-bit tagging rule on all hosts, but the
#   64-bit verifier counts with its own rule, so 0x7fffffff fails with error 1063.
#   64-bit hosts don't use the boxes, so count them the way the compiler does
sed -i 's/(const uint32_t \*)((uint32_t)vmImg->dataEnd & ~0xf)/(const uint32_t *)((uintptr_t)vmImg->dataEnd \& ~(uintptr_t)0xf)/' pxtapp/core---vm/vm.cpp
sed -i 's/aspxt::RefCollection(/asRefCollection(/' pxtapp/pointers.cpp
sed -i 's/if (!canBeTagged(v >> 1))/if ((((int)(v >> 1)) << 1) >> 1 != (int)(v >> 1))/' pxtapp/core---vm/verify.cpp

make -j"$(nproc)" CROSS_TRIPLE=linux build-one > make.log 2>&1 || { tail -30 make.log; exit 1; }
cp bld/libpxt.so "$2/libpxt.so"
gcc -O2 -Wall -std=gnu99 /native/runner.c -o "$2/Game" $(sdl2-config --cflags) -lSDL2
strip "$2/Game"
