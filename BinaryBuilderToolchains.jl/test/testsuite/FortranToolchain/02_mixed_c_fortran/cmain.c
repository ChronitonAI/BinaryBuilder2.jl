#include <stdio.h>

double f_sum_squares(const double *x, int n);
void f_report(double s);

int main(void) {
    double x[] = {1.0, 2.0, 3.0};
    double s = f_sum_squares(x, 3);
    printf("C got: %.1f\n", s);
    fflush(stdout);
    f_report(s);
    return 0;
}
