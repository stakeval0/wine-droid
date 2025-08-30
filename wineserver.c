#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <limits.h>
#include <fcntl.h>
#include <elf.h>
#include <errno.h>

#define PATH_MAX 4096
#define BOX86_PATH "box86"
#define BOX64_PATH "box64"

int main(int argc, char *argv[]) {
    char exe_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len == -1) {
        perror("readlink");
        return 1;
    }
    exe_path[len] = '\0';

    // Get directory path of current binary
    char *dir = strdup(exe_path);
    if (!dir) {
        perror("strdup");
        return 1;
    }

    char *base = basename(exe_path);
    char *dir_path = dirname(dir);

    // Construct wineserver.real path
    char real_path[PATH_MAX];
    snprintf(real_path, sizeof(real_path), "%s/%s.real", dir_path, base);
    free(dir);

    // Open ELF header
    int fd = open(real_path, O_RDONLY);
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

    if (memcmp(e_ident, ELFMAG, SELFMAG) != 0) {
        fprintf(stderr, "Not an ELF file: %s\n", real_path);
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

    // Build new argv list: loader real_path args...
    char **new_argv = malloc(sizeof(char *) * (argc + 2));
    if (!new_argv) {
        perror("malloc");
        return 1;
    }

    new_argv[0] = (char *)loader;
    new_argv[1] = real_path;
    for (int i = 1; i < argc; ++i) {
        new_argv[i + 1] = argv[i];
    }
    new_argv[argc + 1] = NULL;

    execvp(loader, new_argv);
    perror("execvp");
    free(new_argv);
    return 1;
}
