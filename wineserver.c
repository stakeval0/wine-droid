#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <elf.h>
#include <errno.h>

#define TARGET_PATH "/opt/wine/bin/wineserver.real"
#define BOX86_PATH "box86"
#define BOX64_PATH "box64"

int main(int argc, char *argv[]) {
    int fd = open(TARGET_PATH, O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    unsigned char e_ident[EI_NIDENT];
    if (read(fd, e_ident, EI_NIDENT) != EI_NIDENT) {
        perror("read");
        close(fd);
        return 1;
    }
    close(fd);

    // Check ELF magic
    if (memcmp(e_ident, ELFMAG, SELFMAG) != 0) {
        fprintf(stderr, "Not an ELF file: %s\n", TARGET_PATH);
        return 1;
    }

    const char *loader = NULL;

    switch (e_ident[EI_CLASS]) {
        case ELFCLASS32:
            loader = BOX86_PATH;
            break;
        case ELFCLASS64:
            loader = BOX64_PATH;
            break;
        default:
            fprintf(stderr, "Unknown ELF class: %d\n", e_ident[EI_CLASS]);
            return 1;
    }

    // execvp: loader, [loader, wineserver.real, ...]
    char **new_argv = malloc(sizeof(char *) * (argc + 2));
    if (!new_argv) {
        perror("malloc");
        return 1;
    }

    new_argv[0] = (char *)loader;
    new_argv[1] = (char *)TARGET_PATH;
    for (int i = 1; i < argc; ++i) {
        new_argv[i + 1] = argv[i];
    }
    new_argv[argc + 1] = NULL;

    execvp(loader, new_argv);
    perror("execvp");
    free(new_argv);
    return 1;
}
