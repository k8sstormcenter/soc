#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <ns_file> <nstype>\n", argv[0]);
        return 1;
    }

    const char *ns_file = argv[1];
    int nstype = atoi(argv[2]);

    int ns_fd = open(ns_file, O_RDONLY);
    if (ns_fd == -1) {
        perror("open");
        return 1;
    }

    if (setns(ns_fd, nstype) == -1) {
        perror("setns");
        return 1;
    }

    printf("Successfully entered namespace!\n");

    // Keep the process running so you can observe the effect
    while (1) {
        sleep(60);  //adjust the interval for test purposes
    }

    close(ns_fd);
    return 0;
}
