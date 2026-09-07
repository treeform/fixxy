<img src="docs/fixxyBanner.svg" alt="Fixxy fixed-point numbers and 2D vectors">

# Fixxy - Deterministic fixed-point numbers and 2D vectors.

`nimby install https://github.com/treeform/fixxy`

![Github Actions](https://github.com/treeform/fixxy/workflows/Github%20Actions/badge.svg)
![GitHub](https://img.shields.io/github/license/treeform/fixxy)

Fixxy provides Q16.16 arithmetic and `FixedVec2` for deterministic simulations.
The library uses only the Nim standard library.

This repository is private for now. Installation requires Git access to it.
API documentation is available as the `api-docs` artifact in the
[docs workflow](https://github.com/treeform/fixxy/actions/workflows/docs.yml).
The workflow only publishes a website when the repository is public.

## Example

```nim
import fixxy

let
  position = fixedVec2(1, 2)
  target = fixedVec2(4, 6)
  velocity = normalize(target - position) * 0.25'fx
  next = position + velocity

echo next # fixedVec2(1.15001, 2.20000)
```

Use it as a dependency in another package:

```nim
requires "https://github.com/treeform/fixxy"
```

## Numbers

`Fixed` stores a signed Q16.16 value in one `int32`. Its range is -32768 to
just under 32768, with a step size of about 0.00001526 (exactly 1/65536).
Text output rounds values to five decimal places.

- Construct whole numbers with `fixed(3)` and decimals with `1.5'fx`.
- Parse decimal strings with `parseFixed`. Invalid input raises `FixxyError`,
  which inherits from `ValueError`.
- Convert at input and output boundaries with `toFixed`, `toFloat32`,
  `toFloat64`, and `toInt`.
- Arithmetic includes rounding, comparisons, clamping, interpolation,
  `multiplyDivide`, square roots, and trigonometry in radians.
- Multiplication and division round to nearest with ties toward positive
  infinity. Decimal parsing and float conversion round ties away from zero.
- Overflow wraps. Use `-d:fixedChecks` to assert checked intermediate ranges.
  Negation and `abs` of `FixedMinimum` still wrap to `FixedMinimum`.
- Division and modulo by zero raise `AssertionDefect`.

The trigonometry tables are generated at compile time. Tests pin table entries
and the original simulation arithmetic hash to detect changes between builds.
The package targets Nim's native C and C++ backends.

## Vectors

`FixedVec2` contains two `Fixed` coordinates, `x` and `y`, in eight bytes.
It supports component arithmetic, scalar multiplication and division,
indexing, dot and cross products, lengths, distances, normalization,
rotation, angles, and interpolation. Normalizing zero returns zero.

`lengthSquared` and `distanceSquared` return raw Q32.32 values in an `int64`.
Lengths must fit in `Fixed`, and coordinate differences use wrapping fixed
arithmetic. Keep vectors and intermediate results within the numeric range.

## Development

```sh
nim r tests/tests.nim
nim r -d:release tests/tests.nim
nim r -d:fixedChecks tests/tests.nim
nim r examples/movement.nim
```

The optional benchmark uses Benchy:

```sh
nimby install -g benchy
nim r -d:release tests/bench_fixed.nim
```

## Origin

Extracted from [Metta-AI/polyworld](https://github.com/Metta-AI/polyworld),
commit `617cb962ee8e88a256ec2728f9ef82d0b2cb3930`:

- `src/polyworld/fixed.nim`
- `tests/test_fixed.nim`
- `tests/bench_fixed.nim`

The original `Fixed`, `FixedVec2`, constants, and arithmetic are preserved.
Extraction, packaging, documentation, and additional tests were prepared with
AI assistance.
