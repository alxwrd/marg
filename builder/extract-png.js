// Extracts a MakeCode project from a .png export into a directory.
// The decoding follows pxt.Util.decodeBlobAsync in pxtlib/util.ts, which needs a
// browser canvas, and importProjectCoreAsync in webapp/src/app.tsx.
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");
const lzma = require("lzma");

const IMAGE_MAGIC = 0x59347a7d;
const IMAGE_HEADER_SIZE = 36;

function decodeBlob(file) {
  const { data: d, width, height } = PNG.sync.read(fs.readFileSync(file));
  const bpp = (d[0] & 1) | ((d[1] & 1) << 1) | ((d[2] & 1) << 2);
  if (bpp > 5 || bpp == 0) throw new Error("not a MakeCode PNG (bad bit depth)");

  function decode(ptr, bpp, trg) {
    let shift = 0, i = 0, acc = 0;
    const mask = (1 << bpp) - 1;
    while (i < trg.length) {
      acc |= (d[ptr++] & mask) << shift;
      if ((ptr & 3) == 3) ptr++; // skip alpha
      shift += bpp;
      if (shift >= 8) {
        trg[i++] = acc & 0xff;
        acc >>= 8;
        shift -= 8;
      }
    }
    return ptr;
  }

  const hd = Buffer.alloc(IMAGE_HEADER_SIZE);
  const ptr = decode(4, bpp, hd);
  if (hd.readUInt32LE(0) != IMAGE_MAGIC) throw new Error("not a MakeCode PNG (bad magic)");
  const res = Buffer.alloc(hd.readUInt32LE(4));
  const addedLines = hd.readUInt32LE(8);
  if (addedLines > 0) {
    const origSize = (height - addedLines) * width;
    const imgCap = ((origSize - 1) * 3 * bpp) >> 3;
    const tmp = Buffer.alloc(imgCap - IMAGE_HEADER_SIZE);
    decode(ptr, bpp, tmp);
    tmp.copy(res);
    decode(origSize * 4, 8, res.subarray(tmp.length));
  } else {
    decode(ptr, bpp, res);
  }
  return res;
}

function decompress(buf) {
  if (buf[0] == 0x7b) return Promise.resolve(buf.toString("utf8"));
  return new Promise((resolve, reject) =>
    lzma.decompress(buf, (res, err) => err ? reject(err) : resolve(res)));
}

async function main() {
  const [file, outDir] = process.argv.slice(2);
  const project = JSON.parse(await decompress(decodeBlob(file)));
  const files = JSON.parse(project.source);
  for (const name of Object.keys(files)) {
    const dest = path.join(outDir, name);
    if (!path.resolve(dest).startsWith(path.resolve(outDir) + path.sep)) throw new Error("bad file name: " + name);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, files[name]);
  }
  console.log(JSON.stringify(project.meta));
}

main().catch(e => { console.error("extract failed: " + e.message); process.exit(1); });
