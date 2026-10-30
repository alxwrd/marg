# Debian 10 has glibc 2.28, older than the device's 2.30, so what is linked here
# can't need a newer symbol. Debian 10's packages moved to the archive at end of life.
FROM debian:10-slim
RUN printf 'deb http://archive.debian.org/debian buster main\ndeb http://archive.debian.org/debian-security buster/updates main\n' > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends gcc g++ make libc6-dev libsdl2-dev binutils
COPY build-runtime.sh runner.c /native/
