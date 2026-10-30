// Compares a 640x480 screenshot with the game area of a MakeCode share image,
// both reduced to the game's 160x120 pixels. The share image hides the project in
// the low bits of its pixels, so colours only need to be close.
// Usage: compare-colours.js <fixture.png> <screenshot.png>
const fs = require("fs");
const { PNG } = require("pngjs");
const fixture = PNG.sync.read(fs.readFileSync(process.argv[2]));
const shot = PNG.sync.read(fs.readFileSync(process.argv[3]));
const TOLERANCE = 32;

const at = (img, x, y) => [...img.data.subarray((y * img.width + x) * 4, (y * img.width + x) * 4 + 3)];
const hex = c => "#" + c.map(v => v.toString(16).padStart(2, "0")).join("");

let matched = 0, total = 0;
const shotColours = {};
for (let y = 0; y < 120; y++)
  for (let x = 0; x < 160; x++) {
    // Share image game area starts at (16, 16), at 3x. Sample each pixel's centre
    const a = at(fixture, 16 + x * 3 + 1, 16 + y * 3 + 1);
    const b = at(shot, x * 4 + 2, y * 4 + 2);
    total++;
    if (a.every((v, i) => Math.abs(v - b[i]) <= TOLERANCE)) matched++;
    shotColours[hex(b)] = (shotColours[hex(b)] || 0) + 1;
  }
console.log(`${(100 * matched / total).toFixed(1)}% of pixels match`);
console.log("screenshot colours: " + Object.entries(shotColours).sort((a, b) => b[1] - a[1]).map(([c, n]) => `${c}:${n}`).join(" "));
