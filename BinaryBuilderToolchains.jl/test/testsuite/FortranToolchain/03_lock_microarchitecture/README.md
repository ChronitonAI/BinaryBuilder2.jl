# Lock microarchitecture

As for the C toolchain: `$FC -march=...` must fail (we set `-march` ourselves), and `$FC`
must pass our `-march`.
