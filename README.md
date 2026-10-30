# MARG

**M**akeCode **A**rcade for **RG**36S.

Turns a [MakeCode Arcade](https://arcade.makecode.com) `.png` export into a game for an Anbernic RG36S running stock ArkOS (glibc 2.30).

<p>
  <p align="center">
    <img width="100%" src=".github/splash.jpg">
  </p>
  <p align="right">
    <sup>Photo by <a href="https://unsplash.com/@senadpalic">Senad Palic</a>
    on <a href="https://unsplash.com">Unsplash</a>, with title added.
    Title set in <a href="https://fonts.google.com/specimen/Jacquard+24">Jacquard 24</a>.</sup>
  </p>
</p>

## Requirements

- Docker
- An ARM64 host (or via Docker's ARM64 emulation, which hasn't been tested)
- Network access for the first build, and for projects with GitHub extensions

## Usage

```
./build.sh fixtures/arcade-Your-Game.png
```

This writes a folder and a launcher:

```
out/ports/Your_Game/
out/ports/Your Game.sh
```

Copy both to `ports/` on the SD card. The game appears in the Ports menu after EmulationStation restarts. Its image appears after the first launch and the next restart.

## Controls

| Device              | Game          |
| ------------------- | ------------- |
| D-pad or left stick | Move          |
| A, B                | A, B          |
| Start               | MakeCode menu |
| Select + Start      | Quit          |

All controllers act as player 1, so two-player games can't be played yet.

Game logs are `log.txt` and `game.log` in the game's folder. Settings and high scores save to `settings-v0/` there.

## How it works

Everything runs in one Docker image, `builder/Dockerfile`:

1. `pxt`, MakeCode's own compiler, turns the project in the PNG into `game.pxt64`.
2. The same step generates the runtime's C++, which is compiled to `libpxt.so`. A few upstream bugs are patched in `builder/build-runtime.sh`.
3. `builder/runner.c` is compiled to `Game`, a small SDL2 program that runs the image.

Steps 2 and 3 link against Debian 10's glibc 2.28, so the binaries run on the device's 2.30. `build.sh` stops if a binary needs anything newer than 2.30.

## Testing

Tests run in Docker with a virtual display, and don't need the device:

```
test/run-game.sh out/ports/Chase_the_Pizza out/test
```

[PLAN.md](PLAN.md) has more on testing, what Docker can't prove, the device and what we learnt.

## Licence

[MIT](LICENSE), for the code in this project. The output includes MakeCode code under its own MIT licence, so keep `THIRD_PARTY_NOTICES.md` with any game you share. It is copied to each game's folder.
