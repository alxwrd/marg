# Project notes

Device details, test instructions and what we learnt. [README.md](README.md) has how to use the compiler.

## Status

- **The build works.** All of the output is built from source in Docker, and it needs nothing newer than `GLIBC_2.17`.
- **Tested in Docker:** both fixtures run on glibc 2.28 and 2.41 with no panic. Screenshots match the fixtures' colours (99.5% or more of pixels, `test/compare-colours.js`). The keyboard path works: A restarts after game over, Right moves the player, and Esc and SIGTERM exit with code 0. The launcher was dry-run with a fake PortMaster and a stub `Game`.
- **Confirmed on the device (user report):** our output built on Debian 10 with GCC 8 works and looks good. Our `.pxt64` hasn't changed since, byte for byte.
- **Not yet on the device:** `Game` and `libpxt.so` built with the current image (GCC 14 against the Debian 10 sysroot). They pass every Docker test, but they are new binaries, so test them on the device.

## Testing without the device

An Apple silicon Mac can run the ARM64 binaries directly in Docker, with a virtual display. This is far quicker than moving the SD card.

```
test/run-game.sh out/ports/Chase_the_Pizza out/test [Game args...]
```

It writes `run.log` and three screenshots, `a.png` at 3 seconds, `b.png` at 6 seconds and `c.png` at 9 seconds, and prints whether the game is still alive.

**Compare screenshots against the fixture PNGs.** The fixtures are the game's own MakeCode share images, showing the correct colours:
- `fixtures/arcade-Test.png`: a mostly black "Testing game" screen, so it's a weak test of colours.
- `fixtures/arcade-Chase-the-Pizza.png`: teal background, pink score boxes, yellow "GAME OVER". The game reaches this screen by itself within 6 seconds with no input. The screenshot can differ slightly from the PNG in things like the pizza's position and the "A" prompt.

`OLD_GLIBC=1` runs on glibc 2.28 and SDL 2.0.9, which are older than the device. Under Xvfb, SDL 2.0.9 fails to start about 1 run in 6 (`No available video device`) and ignores key presses. Binaries from the older Debian 10 build do the same, so this comes from that test image. Run again if it fails, and test input without `OLD_GLIBC`. `KEYS="z Right"` presses keys through Xvfb after the first screenshot.

`test/compare-colours.js <fixture.png> <screenshot.png>` (run it in the `makecode-build` image, which has `pngjs`) reports how many of the 160x120 pixels match.

#### What Docker can't prove

The container uses a software OpenGL renderer and a dummy audio driver. It has no controller and no `gptokeyb`. Older device-specific failures didn't show up here, so always finish with a device test. Check these on the device:

- **Controls:** `SDL_GAMECONTROLLERCONFIG` from PortMaster, d-pad, stick, and whether A and B are the right way round (SDL's labels, not tested). All controllers act as player 1, so two-player games can't be played yet. Start opens the MakeCode menu.
- **Audio:** the runner opens 44100 Hz, 1 channel, 1024 samples as before, but no sound has been heard from this runtime.
- **Mali rendering:** that SDL picks `opengles2`, that `/usr/local/lib/aarch64-linux-gnu` in `LD_LIBRARY_PATH` finds the right driver, and that vsync works.
- **Screen scaling:** the texture is stretched to the whole display with nearest-neighbour scaling, and `SDL_WINDOW_FULLSCREEN_DESKTOP` is untested on KMS/DRM.
- **Select+Start:** `gptokeyb "Game"` should find the process by name. It has never been confirmed on the device, for any build.
- **The menu image:** the launcher adds the game to `ports/gamelist.xml` on its first run, so the image should appear after EmulationStation next restarts. Whether ES keeps that entry, and shows a 3:2-ish share image well, is untested.
- **Settings:** they save to `settings-v0/` in the game's folder. Check that this works on exFAT.

**Debugging panics with gdb:** add `--cap-add SYS_PTRACE --security-opt seccomp=unconfined` to `docker run`. You can set pending breakpoints on `target_panic` and use `bt`. The image in `test/Dockerfile` includes gdb.

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

### Website builds

Games from the website compiler need a bundled glibc, a palette fix and a separately extracted image. `Delivery.sh` on the card still runs this way, because its PNG isn't available. The instructions and `palette_fix.c` are in git history, in `PLAN.md` and `reference/` at commit `f0750cf`.

### The palette bug

- **Symptom:** `PANIC 911` straight after `start main loop`. 911 is `PANIC_SCREEN_ERROR`.
- **Cause:** `pxt::setPalette` requires a 48-byte buffer (16 RGB colours). Current website builds pass a 6-byte constant, `00 00 00 ff ff ff`, and the default palette is missing from the image.
- **It's the compiler, not the games:**
  - Delivery, Test and Chase the Pizza all have it.
  - `games/ControllerTest` in <https://github.com/Kikketer/CreationStationArcade> (branch `single-native-arcade`) is an older website build. It has the default palette and runs with no fix, and its `libpxt.so` is a different size (267,880 bytes, against 333,568). Its age is unknown.
  - That repo is a launcher, not the compiler.
- **Don't just skip the check:** the runtime then reads 48 bytes anyway, and colours 2 to 15 come from unrelated memory, including pointers. Colours are wrong, and could change between launches.
### Arcade's default palette

```
#000000 #ffffff #ff2121 #ff93c4 #ff8135 #fff609 #249ca3 #78dc52
#003fad #87f2ff #8e2ec4 #a4839f #5c406c #e5cdc4 #91463d #000000
```

This was typed from memory, and it matches the colours in our screenshots of the fixtures.

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
- **`pxt build` calls `make` for all platforms through `crossbuild`.** The image doesn't need that result, so `builder/stub/make` replaces it and `builder/build-runtime.sh` builds the generated tree in `built/dockercross` separately.
- **Strip the source map.** `binary.pxt64` has a source map after the image, and the runtime rejects the file with error 1001 unless the length is a multiple of 8. Website images have no source map. The image size is a 32-bit value at offset `0x48`.
- **The right screen code** is `libs/screen---ext` and `libs/mixer---ext`, which `hw---vm` selects, not `screen---linux`. `pxt-arcade/libs/hw---vm/sdlmain.cpp` is an upstream SDL runner.
- **The website's runtime isn't the public source.** Its `Game` also needs `pxt_screen_get_size`, which public source lacks, so that `Game` can't load our `libpxt.so`. Our own runner doesn't need it.
- **Upstream bugs patched in `builder/build-runtime.sh`:** a truncated pointer in `find_src_map`, `aspxt::RefCollection` from the generator, and validation error 1063 on 64-bit hosts (see the comment there).
- **Palette bug confirmed as the website's:** the website image panics with 911 on our runtime, and our image doesn't.

### Building against an old glibc on a new OS

Passing `--sysroot` isn't enough, because gcc still looks in the host's folders. Use `gcc -Wl,-t` to see what is linked. Each of these got through:

- **Startup files:** `Scrt1.o`, `crti.o` and `crtn.o` came from the host's glibc 2.41. `-B<sysroot lib dir>/` puts the sysroot first.
- **Absolute symlinks:** `libpthread.so` in the sysroot pointed at `/lib/...`, which is the host's empty stub (`undefined reference to pthread_create`). The Dockerfile rewrites them to stay in the sysroot.
- **Libraries that libraries need:** `ld` found the host's `libc.so.6` for the old `libpthread` (`undefined reference to ...@GLIBC_PRIVATE`). `-rpath-link` fixes this.

`crtbeginS.o`, `crtendS.o` and `libgcc` still come from GCC 14. That is correct, and they add no glibc symbols. `build.sh` now fails if a binary needs anything newer than `GLIBC_2.30`.

### Our runner

- **`pxt_get_panic_code` returning -1 means restart.** The runner must call `pxt_vm_start` again. Upstream's `sdlmain.cpp` doesn't, and the screen freezes after A on the game over screen.
- **Settings need a writable folder.** The runtime aborts with `FAILURE: can't write file` otherwise, so the runner falls back to `/tmp` if the folder isn't writable.
- **Xvfb needs time to start,** and SDL fails with `No available video device` if it isn't ready. `test/run-game.sh` waits for it.
- **A share image can't be compared exactly,** because the project is hidden in the low bits of its pixels.
- **Compiling a project needs network** if it has GitHub extensions, like Chase the Pizza.

### Logging on the device

- Output through `tee` wasn't reliable. `log.txt` sometimes came back empty, or kept the previous run's contents after a forced power-off.
- Sending the game's output straight to a file (`game.log`) worked, and it closes when the game exits. The launcher also runs `sync` every second.
- `log.txt` having old contents means the new run didn't save or didn't start, not that the same error happened again.

### macOS and the SD card

- Copying files creates `._*` metadata files. They were harmless for libraries, but `._Something.sh` in `ports/` is not a real script and could appear as a menu entry, so delete them.
- exFAT has no execute permission to speak of, so the launcher runs `chmod` and it hasn't been a problem.
- EmulationStation finds any `.sh` in `ports/`. `gamelist.xml` is optional metadata.

### SSH

USB can't work, because the device's USB port is host-only. Wi-Fi is the realistic route: a USB dongle, then Enable Remote Services, then `ssh ark@<ip>` (password reported to be `ark`). Docker testing has mostly removed the need for it.

## Files in this repo

| Path | What it is |
|---|---|
| `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md` | Usage, and the licence terms for this project and what it builds from |
| `build.sh` | The command: PNG to `out/ports/` |
| `builder/Dockerfile` | The one build image: current Debian, with Debian 10's glibc and SDL in `/sysroot` |
| `builder/build-image.sh`, `extract-png.js`, `pxt.js`, `stub/` | PNG to `.pxt64` and C++ tree |
| `builder/build-runtime.sh`, `runner.c` | Runtime build with its upstream patches, and `Game` |
| `launcher/launcher.sh` | Template for the launcher |
| `test/Dockerfile`, `test/Dockerfile.old-glibc`, `test/run-game.sh`, `test/compare-colours.js` | Run a game, take screenshots with no device, and compare them with a fixture |
| `fixtures/*.png` | MakeCode share images: a source for the compiler and a colour reference |


## Links

- Website compiler: <https://www.makecode.games/compilers/desktop>
- <https://github.com/microsoft/pxt-arcade>
- <https://github.com/microsoft/pxt-common-packages>
- <https://github.com/Kikketer/CreationStationArcade/tree/single-native-arcade>
