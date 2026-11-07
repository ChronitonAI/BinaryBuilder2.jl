#include <stdio.h>

double c_square(double x) {
    return x * x;
}

void c_greet(int n) {
    printf("hello from C, n = %d\n", n);
    fflush(stdout);
}
