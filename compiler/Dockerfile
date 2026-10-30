# Runs the MakeCode compiler. It only makes the architecture independent image,
# so node can be newer than the device's glibc.
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends make python3 ca-certificates git
WORKDIR /pxt
RUN npm init -y > /dev/null && npm install --no-audit --no-fund --omit=optional \
    pxt-arcade@4.1.27 pxt-core@13.1.24 pxt-common-packages@14.1.7 pngjs@7.0.0 lzma@2.3.2
