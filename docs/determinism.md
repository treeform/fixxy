# Determinism tests

`tests/test_determinism.nim` runs from `tests/tests.nim` and checks:

- Every entry of the sine and arctangent tables, including guard entries.
- 4,096 scalar cases covering signed rounding, division, roots, and formatting.
- 4,096 steps of 2D motion, normalization, rotation, and vector geometry.
- Repeated traces with unrelated calculations between runs.

Inputs come from explicit integer seeds. Digests record raw fixed-point bits
in a specified byte order and include text lengths and bytes. They never hash
native object memory, padding, or floating-point representations.

Expected digests are fixed regression values. The scalar and table digests
were also checked with a separate reference calculation. Do not regenerate
expected values merely to make a failing test pass. An intentional arithmetic
or table change needs review for replay compatibility.

Run `nim r tests/tests.nim` or `nim cpp -r -d:release tests/tests.nim`.
CI checks the same values on Linux, macOS, and Windows using C debug, release,
danger, and fixedChecks builds, plus C++ release builds.
