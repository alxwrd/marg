# ARM64 Linux with SDL2, a virtual display and screenshot tools, for running
# Game binaries on an Apple silicon Mac. glibc is new enough for current builds.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsdl2-2.0-0 xvfb imagemagick gdb gcc libc6-dev
