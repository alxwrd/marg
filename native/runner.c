// Runs a MakeCode Arcade image with SDL2. Based on hw---vm/sdlmain.cpp in pxt-arcade.
// Usage: Game [image.pxt64]
// libpxt.so and game.pxt64 are found next to this binary.
#include <SDL.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define WIDTH 160
#define HEIGHT 120
#define FRAME_MS 16

#define INTERNAL_KEY_UP 2050
#define INTERNAL_KEY_DOWN 2051

enum Key { KEY_NONE, KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_A, KEY_B, KEY_MENU, KEY_RESET = 100 };

// The stick counts as the d-pad once it is pushed this far
#define STICK_THRESHOLD 16000

static void (*pxt_screen_get_pixels)(int width, int height, uint32_t *screen);
static void (*pxt_raise_event)(int src, int val);
static void (*pxt_vm_start)(const char *fn);
static void (*pxt_vm_set_data_directory)(const char *path);
static int (*pxt_get_logs)(int logtype, char *dst, int maxSize);
static int (*pxt_get_panic_code)(void);
static void (*pxt_get_audio_samples)(int16_t *buf, unsigned numSamples);

static char logBuf[64 * 1024];

static void fatal(const char *msg, const char *info) {
    fprintf(stderr, "%s %s (SDL error: %s)\n", msg, info, SDL_GetError());
    exit(1);
}

static void *loadFunction(void *lib, const char *name) {
    void *fn = SDL_LoadFunction(lib, name);
    if (!fn)
        fatal("can't find function in libpxt.so:", name);
    return fn;
}

static void loadRuntime(const char *dir) {
    char path[PATH_MAX + 16];
    snprintf(path, sizeof(path), "%s/libpxt.so", dir);
    void *lib = SDL_LoadObject(path);
    if (!lib)
        fatal("can't load", path);
    *(void **)&pxt_screen_get_pixels = loadFunction(lib, "pxt_screen_get_pixels");
    *(void **)&pxt_raise_event = loadFunction(lib, "pxt_raise_event");
    *(void **)&pxt_vm_start = loadFunction(lib, "pxt_vm_start");
    *(void **)&pxt_vm_set_data_directory = loadFunction(lib, "pxt_vm_set_data_directory");
    *(void **)&pxt_get_logs = loadFunction(lib, "pxt_get_logs");
    *(void **)&pxt_get_panic_code = loadFunction(lib, "pxt_get_panic_code");
    *(void **)&pxt_get_audio_samples = loadFunction(lib, "pxt_get_audio_samples");
}

static void raiseKey(enum Key key, int down) {
    int ev = down ? INTERNAL_KEY_DOWN : INTERNAL_KEY_UP;
    pxt_raise_event(ev, key);
    pxt_raise_event(ev, 0); // any key
}

static enum Key mapKeyboard(SDL_Keycode code) {
    switch (code) {
    case SDLK_LEFT: case 'a': return KEY_LEFT;
    case SDLK_RIGHT: case 'd': return KEY_RIGHT;
    case SDLK_UP: case 'w': return KEY_UP;
    case SDLK_DOWN: case 's': return KEY_DOWN;
    case ' ': case 'z': return KEY_A;
    case SDLK_RETURN: case 'x': return KEY_B;
    case 'm': return KEY_MENU;
    case '/': return KEY_RESET;
    default: return KEY_NONE;
    }
}

static enum Key mapButton(int button) {
    switch (button) {
    case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return KEY_LEFT;
    case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return KEY_RIGHT;
    case SDL_CONTROLLER_BUTTON_DPAD_UP: return KEY_UP;
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return KEY_DOWN;
    case SDL_CONTROLLER_BUTTON_A: return KEY_A;
    case SDL_CONTROLLER_BUTTON_B: return KEY_B;
    case SDL_CONTROLLER_BUTTON_START: return KEY_MENU;
    default: return KEY_NONE;
    }
}

// Sends the change of one stick axis as two d-pad keys
static void handleAxis(int value, int *state, enum Key negative, enum Key positive) {
    int next = value < -STICK_THRESHOLD ? -1 : value > STICK_THRESHOLD ? 1 : 0;
    if (next == *state)
        return;
    if (*state)
        raiseKey(*state < 0 ? negative : positive, 0);
    if (next)
        raiseKey(next < 0 ? negative : positive, 1);
    *state = next;
}

static void flushLogs(void) {
    int size;
    while ((size = pxt_get_logs(0, logBuf, sizeof(logBuf) - 1)) > 0)
        fwrite(logBuf, 1, size, stderr);
}

static void audioCallback(void *userdata, Uint8 *stream, int len) {
    (void)userdata;
    pxt_get_audio_samples((int16_t *)stream, len / 2);
}

static SDL_AudioDeviceID openAudio(void) {
    SDL_AudioSpec wanted, actual;
    SDL_zero(wanted);
    wanted.freq = 44100;
    wanted.format = AUDIO_S16SYS;
    wanted.channels = 1;
    wanted.samples = 1024;
    wanted.callback = audioCallback;
    // The game still runs if there is no audio
    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(NULL, 0, &wanted, &actual, 0);
    if (dev)
        fprintf(stderr, "audio: %d Hz, %d ch, %d samples\n", actual.freq, actual.channels, actual.samples);
    else
        fprintf(stderr, "no audio: %s\n", SDL_GetError());
    return dev;
}

int main(int argc, char *argv[]) {
    char dir[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", dir, sizeof(dir) - 1);
    if (len <= 0)
        fatal("can't read", "/proc/self/exe");
    dir[len] = 0;
    *strrchr(dir, '/') = 0;

    char image[PATH_MAX + 16];
    snprintf(image, sizeof(image), "%s/game.pxt64", dir);
    const char *imageName = argc > 1 ? argv[1] : image;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) < 0)
        fatal("can't start SDL", "");

    loadRuntime(dir);
    // Settings go in the game's folder. The runtime aborts if it can't write them,
    // and it uses /tmp if it has no directory
    if (access(dir, W_OK) == 0)
        pxt_vm_set_data_directory(dir);

    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest");
    SDL_Window *window = SDL_CreateWindow("MakeCode Arcade", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                          WIDTH * 4, HEIGHT * 4, SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN_DESKTOP);
    if (!window)
        fatal("can't create window", "");
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer)
        renderer = SDL_CreateRenderer(window, -1, 0);
    if (!renderer)
        fatal("can't create renderer", "");
    SDL_RendererInfo info;
    if (SDL_GetRendererInfo(renderer, &info) == 0)
        fprintf(stderr, "renderer: %s\n", info.name);

    // The runtime writes 0xAARRGGBB, which is BGRA in bytes on this little-endian CPU
    SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, WIDTH, HEIGHT);
    if (!texture)
        fatal("can't create texture", "");
    static uint32_t pixels[WIDTH * HEIGHT];

    SDL_AudioDeviceID audio = openAudio();

    fprintf(stderr, "starting %s\n", imageName);
    pxt_vm_start(imageName);
    if (audio)
        SDL_PauseAudioDevice(audio, 0);

    int quit = 0;
    Uint32 restartAt = 0;
    int stickX = 0, stickY = 0;

    while (!quit) {
        Uint32 frameStart = SDL_GetTicks();

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
            case SDL_QUIT:
                quit = 1;
                break;
            case SDL_KEYDOWN:
            case SDL_KEYUP: {
                if (e.key.repeat)
                    break;
                if (e.key.keysym.sym == SDLK_ESCAPE) {
                    quit = 1;
                    break;
                }
                enum Key key = mapKeyboard(e.key.keysym.sym);
                if (key)
                    raiseKey(key, e.type == SDL_KEYDOWN);
                break;
            }
            case SDL_CONTROLLERDEVICEADDED:
                // Every controller is player 1. The device reports two pads and
                // it is not known which one has the real buttons
                if (SDL_GameControllerOpen(e.cdevice.which))
                    fprintf(stderr, "controller: %s\n", SDL_GameControllerNameForIndex(e.cdevice.which));
                break;
            case SDL_CONTROLLERBUTTONDOWN:
            case SDL_CONTROLLERBUTTONUP: {
                enum Key key = mapButton(e.cbutton.button);
                if (key)
                    raiseKey(key, e.type == SDL_CONTROLLERBUTTONDOWN);
                break;
            }
            case SDL_CONTROLLERAXISMOTION:
                if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX)
                    handleAxis(e.caxis.value, &stickX, KEY_LEFT, KEY_RIGHT);
                else if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY)
                    handleAxis(e.caxis.value, &stickY, KEY_UP, KEY_DOWN);
                break;
            }
        }

        pxt_screen_get_pixels(WIDTH, HEIGHT, pixels);
        SDL_UpdateTexture(texture, NULL, pixels, WIDTH * 4);
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, texture, NULL, NULL);
        SDL_RenderPresent(renderer);

        flushLogs();

        Uint32 now = SDL_GetTicks();
        if (restartAt) {
            if (now >= restartAt) {
                restartAt = 0;
                pxt_vm_start(imageName);
            }
        } else {
            int code = pxt_get_panic_code();
            if (code == -1) {
                // The game asked for this, for example with A on the game over screen
                fprintf(stderr, "reset requested; restarting\n");
                pxt_vm_start(imageName);
            } else if (code >= 1000) {
                fprintf(stderr, "hit soft crash, code=%d; restarting\n", code - 1000);
                restartAt = now + 3000;
            } else if (code > 0) {
                fprintf(stderr, "fatal runtime error %d\n", code);
                flushLogs();
                exit(1);
            }
        }

        // Without vsync, this stops the loop from using a full core
        Uint32 spent = SDL_GetTicks() - frameStart;
        if (spent < FRAME_MS)
            SDL_Delay(FRAME_MS - spent);
    }

    fprintf(stderr, "exit at request\n");
    if (audio)
        SDL_CloseAudioDevice(audio);
    SDL_Quit();
    // The VM's threads are still running, so don't return through static destructors
    _exit(0);
}
