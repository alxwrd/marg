# MakeCode Arcade to RG36S compiler: plan and handover

## Goal

Build our own command that turns a MakeCode Arcade `.png` export into a game that runs on an Anbernic RG36S running ArkOS:

```
./build.sh fixtures/arcade-Chase-the-Pizza.png
# produces a folder and launcher script to copy to ports/ on the SD card
```

The output must run on the device's stock firmware (glibc 2.30) with correct colours and working controls. It should not need the workarounds described below: a bundled glibc, a palette fix or a separately extracted `.pxt64`.

## Why we're doing this

Games can already be compiled at <https://www.makecode.games/compilers/desktop>, but that compiler's source isn't available and its output has two problems on this device:

1. It targets glibc 2.38, and the device has 2.30.
2. Current builds contain a broken 2-colour palette, so they panic on startup on any Linux system.

We have working workarounds, so this project isn't urgent. A game built by the website does run on the device. See [Current working setup](#current-working-setup).

## Status

- **Step 1 works.** `pxt build --hw vm` makes a `.pxt64` in Docker with no cloud service. It contains the default palette, and it runs on the website's `Game` and `libpxt.so` with correct colours and no palette fix.
- **Step 2 works.** `libpxt.so` builds from source on Debian 10 and needs nothing newer than `GLIBC_2.17`. It loads and runs both images, tested with the headless `pxt-vm-cli-linux` from the same build.
- **Confirmed on the device:** Chase the Pizza, built by the website and using the workarounds, was reported by the user as running great.
- **Not separately confirmed on the device:** Select+Start quitting, and whether Delivery's colours match the MakeCode simulator.

## Plan

Do steps 1 and 2 first. They're the riskiest, and they need only Docker. Don't write the runner until they work.

### Step 1: build the game image

In a Docker container, extract the project from a fixture PNG and compile it with the `pxt` CLI using the `vm` variant.

- **Success:** we get a `.pxt64` that runs on the existing `Game` and `libpxt.so` with correct colours and without the palette fix. Compare screenshots against the fixture PNG.
- **Biggest unknown:** whether `pxt build` can produce a `.pxt64` locally. It may need specific tool versions or a cloud service.
- **Useful leads (not yet tried):**
  - `microsoft/pxt-arcade` (MIT) has a `vm` variant in `pxtarget.json` and `libs/hw---vm`.
  - The MakeCode code can already read projects out of PNGs, so reuse it instead of writing a decoder.

### Step 2: build the runtime

Compile `libpxt.so` from `microsoft/pxt-common-packages` (MIT, see `libs/core---vm`) in an old Linux container, targeting glibc 2.30 or older.

- **Success:** the result needs no symbol newer than `GLIBC_2.30`, and it loads the image from step 1. Check with `objdump -T libpxt.so | grep GLIBC`.
- **Risks:**
  - The runtime may expect a particular build setup or compiler.
  - Public source may not match the API the website's build exposes.
  - `libs/screen---linux/screen.cpp` is a `/dev/fb0` version, while the website's build exposes `pxt_screen_get_pixels` for SDL. The right screen code is probably somewhere else, so find that first.

### Step 3: write the runner

Write a small SDL2 program in C to replace `Game`, covering video, input and audio. Build it with the same old toolchain. [Runner and runtime API](#runner-and-runtime-api) lists what it has to call.

Requirements:
- Use the device's SDL2 and honour `SDL_GAMECONTROLLERCONFIG`.
- Scale 160x120 to fill the screen.
- Keep the process name predictable, because `gptokeyb` uses it for Select+Start to quit.

### Step 4: wrap it up

Write `build.sh` so one PNG produces a folder plus a launcher. Base the launcher on `reference/launcher-example.sh`, and drop the workarounds that are no longer needed.

### Step 5: test on the device

Test Chase the Pizza first, because its correct behaviour is known. Then test a game with more colours.

### Fallbacks

- **Step 2 fails:** keep the website's `libpxt.so` and the bundled glibc. Step 1 still gives correct palettes, including custom ones.
- **Step 1 fails:** keep the current setup. It works, but custom palettes need adding to `palette_fix.c` by hand.

## Testing without the device

An Apple silicon Mac can run the ARM64 binaries directly in Docker, with a virtual display. This is far quicker than moving the SD card.

```
test/run-game.sh <dir with Game and libpxt.so> <output dir> [--palette-fix] [Game args...]

# Example, reproduces the panic:
test/run-game.sh ~/Downloads/Chase_the_Pizza-arm64 out/unfixed

# Example, runs with the palette fix and takes screenshots:
test/run-game.sh ~/Downloads/Chase_the_Pizza-arm64 out/fixed --palette-fix
```

It writes `run.log` and two screenshots, `a.png` at 3 seconds and `b.png` at 6 seconds, and prints whether the game is still alive. Both example commands have been run and give those results.

**Compare screenshots against the fixture PNGs.** The fixtures are the game's own MakeCode share images, showing the correct colours:
- `fixtures/arcade-Test.png`: a mostly black "Testing game" screen, so it's a weak test of colours.
- `fixtures/arcade-Chase-the-Pizza.png`: teal background, pink score boxes, yellow "GAME OVER". The game reaches this screen by itself within 6 seconds with no input. The screenshot can differ slightly from the PNG in things like the pizza's position and the "A" prompt.

**What Docker can't prove:** controls, real audio, and anything tied to the device's Mali GPU or screen. The container uses a software OpenGL renderer and a dummy audio driver, and sends no input. Older device-specific failures didn't show up here, so always finish with a device test.

**Debugging panics with gdb:** add `--cap-add SYS_PTRACE --security-opt seccomp=unconfined` to `docker run`. `target_panic` and `_ZN3pxt10setPaletteEPNS_11BoxedBufferE` are exported from `libpxt.so`, so you can set pending breakpoints on them and use `bt`. The image in `test/Dockerfile` includes gdb.

**Checking a `.pxt64` or `Game` for the bad palette:**
- Bad: contains the bytes `06 00 00 00 00 00 00 ff ff ff`.
- Good: contains `00 00 00 ff ff ff ff 21 21 ff 93 c4`.

## The device

| | |
|---|---|
| Hostname and kernel | `rg351mp`, Linux 5.10.160, aarch64 |
| OS | ArkOS, user `ark` (uid 1002), Ubuntu-style file layout |
| glibc | 2.30 |
| SDL2 | `/usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0`, resolving to 2.28.2 |
| GPU libraries | `/usr/local/lib/aarch64-linux-gnu/libmali-bifrost-g31-rxp0-gbm.so`, plus `libEGL`, `libGLESv2` and `libgbm` symlinks |
| Renderer | SDL picks `opengles2` |
| Audio | `rockchip-rk817`, opened at 44100 Hz, 1 channel, 1024 samples |
| Controllers | SDL reports `gamepad` twice, as players 1 and 2 |
| Game path | `/roms/ports/` on the device, which is `/Volumes/EASYROMS/ports/` on the Mac |
| PortMaster | Used for controls and `gptokeyb`. On-device paths are tried in the launcher |

**SD card:** the Mac mounts only `EASYROMS` (exFAT). The boot partition is `disk4s1` and the root filesystem is `disk4s2`, which macOS can't read. The disk number may change.

## What we learnt

Each of these caused a real failure.

### Library loading

- **glibc:** the website's `Game` and `libpxt.so` need glibc 2.38. On the device this fails with ``version `GLIBC_2.38' not found``. We bundle glibc 2.41 from Debian 13's `libc6` arm64 package and start the game with `./libs/ld-linux-aarch64.so.1 --library-path ... ./Game`.
- **Bundle the whole glibc family:** `libc`, `libm`, `libmvec`, `libdl`, `libpthread`, `librt`, `libutil`, `libresolv`, `libnss_files` and `libnss_dns`. Old system copies could clash with the new `libc`.
- **Starting through the loader has side effects:**
  - `/proc/self/exe` points at the loader. `Game` uses it to find its embedded image and appears to use it to find `libpxt.so`.
  - Without a fix, `Game` exits with `no .pxt64 file argument and no embedded image`. So we pass the image as an argument and put a copy of `libpxt.so` in `libs/`.
  - The process name becomes `ld-linux-aarch64.so.1`, so `gptokeyb` must be given that name.
- **Graphics library path:** the bundled loader doesn't find libraries through the system cache, and `/usr/lib/aarch64-linux-gnu/libEGL.so.1` is the wrong driver. Using it gives `file /dev/mali0 is not of a compatible version (user 10.6, kernel 11.38)` and then `Invalid window`. `/usr/local/lib/aarch64-linux-gnu` must come first in the library path.

A binary built properly against glibc 2.30 avoids all of this.

### The palette bug

- **Symptom:** `PANIC 911` straight after `start main loop`. 911 is `PANIC_SCREEN_ERROR`.
- **Cause:** `pxt::setPalette` requires a 48-byte buffer (16 RGB colours). Current website builds pass a 6-byte constant, `00 00 00 ff ff ff`, and the default palette is missing from the image.
- **It's the compiler, not the games:**
  - Delivery, Test and Chase the Pizza all have it.
  - `games/ControllerTest` in <https://github.com/Kikketer/CreationStationArcade> (branch `single-native-arcade`) is an older website build. It has the default palette and runs with no fix, and its `libpxt.so` is a different size (267,880 bytes, against 333,568). Its age is unknown.
  - That repo is a launcher, not the compiler.
- **Don't just skip the check:** the runtime then reads 48 bytes anyway, and colours 2 to 15 come from unrelated memory, including pointers. Colours are wrong, and could change between launches.
- **Our workaround:** `reference/palette_fix.c`, loaded with `LD_PRELOAD`, replaces any wrong-sized palette with the default.
  - It finds the real function through `dladdr` on its caller, because `libpxt.so` is opened privately and `RTLD_NEXT` can't see it (the game died without any panic message when it tried).
  - It can't restore a project's custom palette.

### Arcade's default palette

```
#000000 #ffffff #ff2121 #ff93c4 #ff8135 #fff609 #249ca3 #78dc52
#003fad #87f2ff #8e2ec4 #a4839f #5c406c #e5cdc4 #91463d #000000
```

This was typed from memory. It looks right against the fixtures, but check it against the MakeCode source.

### Runner and runtime API

`Game` is a small SDL2 program (about 200 KB, including the game image). It has no debug symbols, but these names are visible.

**`libpxt.so` functions it looks up with `SDL_LoadFunction`:**
`pxt_screen_get_pixels`, `pxt_screen_get_size`, `pxt_vm_start`, `pxt_vm_start_buffer`, `pxt_raise_event`, `pxt_get_logs`, `pxt_get_panic_code`, `pxt_get_audio_samples`

`libpxt.so` also exports `pxt_vm_set_data_directory`, `pxt_vm_cache_hit`, `pxt_vm_save_in_cache` and `pxt_vm_cache_start`. None of the signatures are known, so get them from source or disassembly.

**Embedded image format:** the image is appended after the end of the ELF file, followed by a 16-byte trailer: the 8 bytes `PXT64BIN`, then the image size as a little-endian 64-bit integer. The image itself starts with a header that includes `PXT64`. To extract it, read the size from the trailer and take that many bytes before the trailer. This was checked on Delivery and Chase the Pizza, where the start offset matched the end of the ELF exactly.

**Other runner behaviour, from its strings and logs:**
- It accepts a `.pxt64` file argument and `--fullscreen`. The CreationStationArcade readme also uses `./Game -f`.
- It handles controllers and joysticks by hot-plug, up to a limit per player.
- It has optional GPIO button support through `/etc/arcade.cfg` or `ARCADE_GPIO_CFG`. We don't need this.
- It logs messages for `exit at key request`, `reset requested; restarting` and `hit soft crash, code=%d; restarting`. Our runner should handle these cases too.

**Runtime screen size:** the runtime uses config keys 37 and 38, defaulting to 160x120, with override keys 2102 and 2103. Upstream's framebuffer version defaults to 160x128, so check for this if you see a screen size mismatch.

**Upstream panic codes** are in `libs/base/pxtbase.h` in `pxt-common-packages`.

### Building from source

- **Pin the versions together.** `pxt-core` newer than the target expects emits `pxtrt::mapSetByStringOnly`, which the bundled libraries lack (`TS9200: missing function`). We use arcade 4.1.27, core 13.1.24 and common-packages 14.1.7, which are the versions the fixtures were saved with. A PNG from a much newer editor may need these raised.
- **Run the CLI against the target:** `mainCli("/pxt/node_modules/pxt-arcade")`, otherwise it uses `pxt-core` itself as the target and can't find `device`.
- **`pxt build` calls `make` for all platforms through `crossbuild`.** The image doesn't need that result, so `compiler/stub/make` replaces it and `native/build-runtime.sh` builds the generated tree in `built/dockercross` separately.
- **Strip the source map.** `binary.pxt64` has a source map after the image, and the runtime rejects the file with error 1001 unless the length is a multiple of 8. Website images have no source map. The image size is a 32-bit value at offset `0x48`.
- **The right screen code** is `libs/screen---ext` and `libs/mixer---ext`, which `hw---vm` selects, not `screen---linux`. `pxt-arcade/libs/hw---vm/sdlmain.cpp` is an upstream SDL runner.
- **The website's runtime isn't the public source.** Its `Game` also needs `pxt_screen_get_size`, which public source lacks, so that `Game` can't load our `libpxt.so`. Our own runner doesn't need it.
- **Upstream bugs patched in `native/build-runtime.sh`:** a truncated pointer in `find_src_map`, `aspxt::RefCollection` from the generator, and validation error 1063 on 64-bit hosts (see the comment there).
- **Palette bug confirmed as the website's:** the website image panics with 911 on our runtime, and our image doesn't.

### Logging on the device

- Output through `tee` wasn't reliable. `log.txt` sometimes came back empty, or kept the previous run's contents after a forced power-off.
- Sending the game's output straight to a file (`game.log`) worked, and it closes when the game exits. The launcher also runs `sync` every second.
- `log.txt` having old contents means the new run didn't save or didn't start, not that the same error happened again.

### macOS and the SD card

- Copying files creates `._*` metadata files. They were harmless for libraries, but `._Something.sh` in `ports/` is not a real script and could appear as a menu entry, so delete them.
- exFAT has no execute permission to speak of, so the launcher runs `chmod` and it hasn't been a problem.
- EmulationStation finds any `.sh` in `ports/`. `gamelist.xml` is optional metadata.

### SSH: not worth pursuing right now

- **USB doesn't work.** The device tree sets `dr_mode: host` on `usb@ff300000`, so `/sys/class/udc` stays empty, even after writing `peripheral` to `otg_mode`. Using USB as a device would need a patched DTB in the boot partition, and the board's wiring may still rule it out.
- **Even then, no USB networking on a Mac.** The kernel has RNDIS but not ECM or NCM. It does have ACM, so a serial shell might be possible.
- **Community scripts don't solve this.** `SSH-over-OTG-for-ArkOS` and `arkos-usb-network-mode` both need a device controller to already exist.
- **Wi-Fi is the realistic route:** a USB dongle in the OTG port, then Enable Remote Services in the Options menu, then `ssh ark@<ip>`. The password is reported to be `ark`. The device has no built-in Wi-Fi as far as we know.
- SSH itself starts fine on the device. Docker testing has mostly removed the need for it.
- `ports/USB SSH.sh` and `ports/usb-ssh.log` from that experiment are still on the card and can be deleted.

## Current working setup

To add a game built by the website without our compiler:

1. Download the `arm64` build from the website and extract it.
2. Create `ports/<Name>-arm64/` on the card, and copy in `Game` and `libpxt.so`.
3. Extract the image to `game.pxt64` in that folder.
4. Create `libs/` in that folder. Copy in the glibc files listed above, `libpalette_fix.so` and a second copy of `libpxt.so`.
5. Copy `reference/launcher-example.sh` to `ports/<Name>.sh` and change `GAMEDIR`.

`Delivery.sh` and `Chase the Pizza.sh` on the card are working examples. Delivery's image is named `delivery.pxt64`, and it still writes `diag.txt` on each launch.

**To rebuild `libpalette_fix.so`:** compile `reference/palette_fix.c` for ARM64 with `gcc -shared -fPIC -O2`, on any system with glibc 2.41 or older (it uses `dlsym` from 2.34, so 2.34 is the minimum, and it runs against the bundled glibc). The working binary is in `libs/` of each game on the card.

## Files in this repo

| Path | What it is |
|---|---|
| `test/Dockerfile`, `test/run-game.sh` | Run a game and take screenshots with no device |
| `reference/palette_fix.c` | Source of the palette workaround |
| `reference/launcher-example.sh` | Launcher for a website build. Rewritten from the card's version when the card was out, so compare it with `ports/Chase the Pizza.sh` if something behaves differently |
| `fixtures/*.png` | MakeCode share images: a source for the compiler and a colour reference |

Website builds used for comparison are in `~/Downloads` (`Test-arm64`, `Chase_the_Pizza-arm64`), and aren't in the repo. Delivery's PNG isn't available, only its build on the card.

## Links

- Website compiler: <https://www.makecode.games/compilers/desktop>
- <https://github.com/microsoft/pxt-arcade>
- <https://github.com/microsoft/pxt-common-packages>
- <https://github.com/Kikketer/CreationStationArcade/tree/single-native-arcade>
