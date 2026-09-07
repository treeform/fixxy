import
  std/[strutils, unittest],
  fixxy

const
  HashStart = 0xcbf29ce484222325'u64
  HashPrime = 0x100000001b3'u64
  ExpectedTables = 0x78d8d8a167478647'u64
  ExpectedScalars = 0x345e4b80f4b22b47'u64
  ExpectedVectors = 0xec338d3dee1a70ef'u64

proc record(hash: var uint64, value: int64) =
  ## Hashes eight bytes in little-endian order without native memory layout.
  let bits = cast[uint64](value)
  for shift in countup(0, 56, 8):
    hash = (hash xor ((bits shr shift) and 255)) * HashPrime

proc record(hash: var uint64, value: Fixed) =
  ## Hashes the signed raw Q16.16 bits in a portable representation.
  hash.record(int64(int32(value)))

proc record(hash: var uint64, value: FixedVec2) =
  ## Records vector coordinates explicitly, without object padding.
  hash.record(value.x)
  hash.record(value.y)

proc record(hash: var uint64, value: string) =
  ## Includes string length and bytes to preserve record boundaries.
  hash.record(int64(value.len))
  for character in value:
    hash = (hash xor uint64(ord(character))) * HashPrime

proc next(state: var uint32): uint32 =
  ## Produces portable corpus inputs without a platform random generator.
  state = state xor (state shl 13)
  state = state xor (state shr 17)
  state = state xor (state shl 5)
  return state

proc scalarTrace(): uint64 =
  ## Exercises signed rounding, scalar math, and decimal round trips.
  result = HashStart
  var state = 0x13579bdf'u32
  for i in 0 ..< 4096:
    let
      left = Fixed(int32(next(state) mod 2_097_153) - 1_048_576)
      magnitude = int32(next(state) mod 1_040_384) + 8192
      right = Fixed(if (next(state) and 1) == 0: magnitude else: -magnitude)
    for value in [
      left + right, left - right, left * right, left / right,
      multiplyDivide(left, right, 0.125'fx), floorMod(left, right),
      sqrt(abs(left)), hypot(left, right),
      floor(left), ceil(left), round(left)
    ]:
      result.record(value)
    result.record(int64(cmp(int32(left), int32(right))))
    result.record($left)
    doAssert parseFixed($left) == left
  for value in [
    FixedMinimum, FixedMaximum, -FixedEpsilon, FixedZero, FixedEpsilon,
    Fixed(-32769), Fixed(-32768), Fixed(-32767),
    Fixed(32767), Fixed(32768), Fixed(32769)
  ]:
    result.record(value * FixedHalf)
    result.record(value / 2'i32)
    result.record($value)
    doAssert parseFixed($value) == value

proc vectorTrace(): uint64 =
  ## Replays planar motion and records each intermediate geometric result.
  result = HashStart
  var
    state = 0x2468ace1'u32
    position = fixedVec2(1.25'fx, -2.5'fx)
    velocity = fixedVec2(0.125'fx, 0.25'fx)
  for i in 0 ..< 4096:
    let
      turn = Fixed(int32(next(state) mod 4097) - 2048)
      target = fixedVec2(
        Fixed(int32(next(state) mod 1_048_577) - 524288),
        Fixed(int32(next(state) mod 1_048_577) - 524288)
      )
      offset = target - position
      heading = normalize(offset)
    velocity = rotate(velocity, turn) * 0.75'fx + heading * 0.125'fx
    position = clamp(position + velocity, -8.0'fx, 8.0'fx)
    result.record(position)
    result.record(velocity)
    result.record(heading)
    result.record(lengthSquared(offset))
    result.record(distance(position, target))
    result.record(dot(velocity, heading))
    result.record(cross(velocity, heading))
    result.record(angle(velocity))
    result.record(direction(angle(velocity)))
    result.record(perpendicular(heading))
    result.record(lerp(position, target, 0.125'fx))

suite "fixxy determinism":
  test "every trigonometry table entry has stable raw bits":
    var hash = HashStart
    hash.record(int64(SineTable.len))
    for value in SineTable:
      hash.record(int64(value))
    hash.record(int64(ArctangentTable.len))
    for value in ArctangentTable:
      hash.record(int64(value))
    doAssert hash == ExpectedTables, "tables: " & toHex(hash)

  test "scalar corpus has a fixed cross-platform digest":
    let first = scalarTrace()
    doAssert first == ExpectedScalars, "scalars: " & toHex(first)
    doAssert scalarTrace() == first

  test "vector replay has a fixed cross-platform digest":
    let first = vectorTrace()
    doAssert first == ExpectedVectors, "vectors: " & toHex(first)
    discard scalarTrace()
    doAssert vectorTrace() == first
