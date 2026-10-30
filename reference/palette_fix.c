// Replaces the wrong-sized palette from the makecode.games compiler with the
// default MakeCode Arcade palette, which is what the runtime needs.
#define _GNU_SOURCE
#include <dlfcn.h>

struct boxed_buffer {
    void *vtable;
    int length;
    unsigned char data[48];
};

static struct boxed_buffer defaults = {
    0, 48,
    {0x00,0x00,0x00, 0xff,0xff,0xff, 0xff,0x21,0x21, 0xff,0x93,0xc4,
     0xff,0x81,0x35, 0xff,0xf6,0x09, 0x24,0x9c,0xa3, 0x78,0xdc,0x52,
     0x00,0x3f,0xad, 0x87,0xf2,0xff, 0x8e,0x2e,0xc4, 0xa4,0x83,0x9f,
     0x5c,0x40,0x6c, 0xe5,0xcd,0xc4, 0x91,0x46,0x3d, 0x00,0x00,0x00},
};

void _ZN3pxt10setPaletteEPNS_11BoxedBufferE(struct boxed_buffer *buf) {
    static void (*real)(struct boxed_buffer *);
    if (!real) {
        // libpxt.so is opened privately, so find it through our caller
        Dl_info info;
        dladdr(__builtin_return_address(0), &info);
        void *lib = dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD);
        real = dlsym(lib, "_ZN3pxt10setPaletteEPNS_11BoxedBufferE");
    }
    real(buf->length == 48 ? buf : &defaults);
}
