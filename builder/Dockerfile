# The one image that does the whole build. It runs on current Debian, and links
# against old libraries, so that the binaries run on the device's glibc 2.30.

# Only supplies the sysroot. Debian 10 has glibc 2.28 and its packages are in the archive.
FROM debian:10-slim AS old-libs
RUN printf 'deb http://archive.debian.org/debian buster main\ndeb http://archive.debian.org/debian-security buster/updates main\n' > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends libc6-dev linux-libc-dev libsdl2-dev

FROM node:24-trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ make binutils ca-certificates
COPY --from=old-libs /usr/include /sysroot/usr/include
COPY --from=old-libs /usr/lib/aarch64-linux-gnu /sysroot/usr/lib/aarch64-linux-gnu
COPY --from=old-libs /lib/aarch64-linux-gnu /sysroot/lib/aarch64-linux-gnu
COPY --from=old-libs /lib/ld-linux-aarch64.so.1 /sysroot/lib/ld-linux-aarch64.so.1
# Absolute symlinks like libpthread.so would point at this image's newer glibc
RUN find /sysroot -type l -lname '/*' | while read -r link; do \
      ln -sf "/sysroot$(readlink "$link")" "$link"; \
    done
WORKDIR /pxt
RUN npm init -y > /dev/null && npm install --no-audit --no-fund --omit=optional \
    pxt-arcade@4.1.27 pxt-core@13.1.24 pxt-common-packages@14.1.7 pngjs@7.0.0 lzma@2.3.2
COPY . /builder/
ENV NODE_PATH=/pxt/node_modules
