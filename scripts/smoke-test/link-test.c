#include <webgpu/webgpu.h>
#include <stdio.h>

int main(void) {
    WGPUInstance instance = wgpuCreateInstance(NULL);
    if (instance == NULL) {
        fprintf(stderr, "wgpuCreateInstance returned NULL\n");
        return 1;
    }
    wgpuInstanceRelease(instance);
    printf("dawn-packer smoke test OK\n");
    return 0;
}
