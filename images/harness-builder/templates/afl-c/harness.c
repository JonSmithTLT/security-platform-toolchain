#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        return 0;
    }
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        return 1;
    }
    unsigned char buf[4096];
    size_t n = fread(buf, 1, sizeof(buf), fp);
    fclose(fp);
    if (n >= 4 && buf[0] == 'F' && buf[1] == 'U' && buf[2] == 'Z' && buf[3] == 'Z') {
        return 0;
    }
    return 0;
}
