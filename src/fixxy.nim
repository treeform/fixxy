## Deterministic Q16.16 fixed-point numbers.
##
## A `Fixed` value is one `int32` holding a signed 16.16 number: the high 16
## bits are the whole part and the low 16 bits are the fraction, so the value
## is simply the integer divided by 65536. The range is -32768 to just under
## 32768, with a step size of about 0.00001526 (exactly 1/65536).
## Text output rounds values to five decimal places.
##
## The layout is plain two's complement, not a pair of separate 16-bit fields.
## That is what makes addition, subtraction, negation, and comparison identical
## to `int32` arithmetic. Multiplication and division widen to `int64` and
## shift the result back down.
##
## Every operation here is exactly reproducible on any platform and any
## compiler, which is what the simulation and its replay hashes depend on.
## Floating point appears in only two places: the conversions at the render
## boundary, and the compile-time generation of the trigonometry tables whose
## integer results are baked into the binary.
##
## Overflow wraps like `int32` rather than raising, so results stay defined.
## Compiling with `-d:fixedChecks` turns the overflow and range rules into
## assertions without costing anything in a normal build.

import
  std/bitops,
  std/math as stdMath

# Overflow is defined here as wrapping, and the widened intermediates are
# proven to fit, so the compiler's overflow traps only cost time. Building
# with -d:fixedChecks reinstates the same guarantee as explicit assertions.
# Bounds checks stay on, since the table lookups benefit from them.
{.push overflowChecks: off.}

## Type and constants

type
  FixxyError* = object of ValueError
    ## Invalid fixed-point input.
  Fixed* = distinct int32
  FixedVec2* = object
    ## Two-dimensional vector with fixed-point coordinates.
    x*, y*: Fixed

const
  FixedShift* = 16
    ## Number of fraction bits.
  FixedScale* = 1'i64 shl FixedShift
    ## Number of fixed-point steps in one whole unit.
  FixedRounding = 1'i64 shl (FixedShift - 1)
    ## Half a step, added before a shift to round to nearest.

const
  FixedZero* = Fixed(0)
  FixedOne* = Fixed(FixedScale)
  FixedHalf* = Fixed(FixedScale div 2)
  FixedEpsilon* = Fixed(1)
    ## Smallest representable step, about 0.00001526 (exactly 1/65536).
  FixedMaximum* = Fixed(high(int32))
    ## Largest value, just under 32768.
  FixedMinimum* = Fixed(low(int32))
    ## Smallest value, -32768.
  FixedPi* = Fixed(205887)
  FixedTau* = Fixed(411775)
  FixedHalfPi* = Fixed(102944)
  FixedVec2Zero* = FixedVec2(x: FixedZero, y: FixedZero)
    ## Vector with both coordinates set to zero.
  FixedVec2One* = FixedVec2(x: FixedOne, y: FixedOne)
    ## Vector with both coordinates set to one.

const InverseTau = 683565276'i64
  ## Rounded 2^32 divided by tau, used to turn radians into a turn fraction.

## Internal helpers

proc checked(value: int64): int64 {.inline.} =
  ## Asserts a widened result still fits in the fixed-point range.
  when defined(fixedChecks):
    doAssert value >= int64(low(int32)) and value <= int64(high(int32)),
      "fixed-point overflow"
  value

proc narrow(value: int64): Fixed {.inline.} =
  ## Truncates a widened result back to the stored 32 bits, wrapping.
  Fixed(cast[int32](cast[uint32](checked(value))))

proc floorDivide(numerator, denominator: int64): int64 {.inline.} =
  ## Divides rounding toward negative infinity, for a positive denominator.
  let quotient = numerator div denominator
  if numerator mod denominator != 0 and numerator < 0:
    quotient - 1
  else:
    quotient

## Construction and extraction

proc fixed*(value: int32): Fixed {.inline.} =
  ## Converts a whole number into a fixed-point value.
  narrow(int64(value) shl FixedShift)

proc fixed*(whole: int16, fraction: uint16): Fixed {.inline.} =
  ## Builds a fixed-point value from its whole and fractional halves.
  Fixed(cast[int32]((cast[uint32](int32(whole)) shl FixedShift) or
    uint32(fraction)))

proc toFixed*(value: float64): Fixed =
  ## Converts a float at an import boundary. Never call this inside a tick.
  narrow(int64(stdMath.round(value * float64(FixedScale))))

proc toFixed*(value: float32): Fixed =
  ## Converts a float at an import boundary. Never call this inside a tick.
  toFixed(float64(value))

proc toFloat64*(value: Fixed): float64 {.inline.} =
  ## Converts to a float at the render boundary. Never call this inside a tick.
  float64(int32(value)) / float64(FixedScale)

proc toFloat32*(value: Fixed): float32 {.inline.} =
  ## Converts to a float at the render boundary. Never call this inside a tick.
  float32(toFloat64(value))

proc whole*(value: Fixed): int32 {.inline.} =
  ## Returns the whole part, rounding toward negative infinity.
  ##
  ## This is the high half of the stored bits, so negatives floor: the whole
  ## part of -1.5 is -2 and its fraction is 0.5.
  int32(value).ashr(FixedShift)

proc fraction*(value: Fixed): uint16 {.inline.} =
  ## Returns the fractional part as a count of 1/65536 steps.
  ##
  ## This is the low half of the stored bits, always positive. The fraction of
  ## -1.5 is 0x8000, because -1.5 is -2 plus 0.5.
  uint16(cast[uint32](int32(value)) and 0xFFFF'u32)

proc toInt*(value: Fixed): int32 {.inline.} =
  ## Returns the whole part, rounding toward zero.
  int32(int64(int32(value)) div FixedScale)

proc floor*(value: Fixed): Fixed {.inline.} =
  ## Rounds down to the nearest whole value.
  Fixed(int32(value) and not int32(FixedScale - 1))

proc ceil*(value: Fixed): Fixed {.inline.} =
  ## Rounds up to the nearest whole value.
  narrow(int64(int32(value)) + FixedScale - 1).floor

proc round*(value: Fixed): Fixed {.inline.} =
  ## Rounds to the nearest whole value, with halves going up.
  narrow(int64(int32(value)) + FixedRounding).floor

## Literals

proc parseFixed*(text: string): Fixed =
  ## Parses a decimal string exactly, using integer arithmetic only.
  var
    index = 0
    negative = false
  if index < text.len and (text[index] == '-' or text[index] == '+'):
    negative = text[index] == '-'
    index += 1
  var whole = 0'i64
  var digits = 0
  while index < text.len and text[index] in {'0' .. '9', '_'}:
    if text[index] != '_':
      whole = whole * 10 + int64(ord(text[index]) - ord('0'))
      digits += 1
      if whole > 32768:
        raise newException(FixxyError, "fixed literal out of range: " & text)
    index += 1
  var fraction = 0'i64
  var scale = 1'i64
  if index < text.len and text[index] == '.':
    index += 1
    while index < text.len and text[index] in {'0' .. '9', '_'}:
      if text[index] != '_':
        if scale < 1_000_000_000:
          fraction = fraction * 10 + int64(ord(text[index]) - ord('0'))
          scale = scale * 10
        digits += 1
      index += 1
  if index != text.len or digits == 0:
    raise newException(FixxyError, "malformed fixed literal: " & text)
  let magnitude = whole * FixedScale +
    (fraction * FixedScale + scale div 2) div scale
  if magnitude > (if negative: -int64(low(int32)) else: int64(high(int32))):
    raise newException(FixxyError, "fixed literal out of range: " & text)
  narrow(if negative: -magnitude else: magnitude)

proc `'fx`*(literal: string): Fixed =
  ## Custom literal so constants read as `1.5'fx` with no float involved.
  parseFixed(literal)

## Comparison

proc `==`*(left, right: Fixed): bool {.borrow.}
proc `<`*(left, right: Fixed): bool {.borrow.}
proc `<=`*(left, right: Fixed): bool {.borrow.}

## Addition and subtraction

proc `+`*(left, right: Fixed): Fixed {.inline.} =
  ## Adds two values, wrapping on overflow.
  when defined(fixedChecks):
    discard checked(int64(int32(left)) + int64(int32(right)))
  Fixed(int32(left) +% int32(right))

proc `-`*(left, right: Fixed): Fixed {.inline.} =
  ## Subtracts two values, wrapping on overflow.
  when defined(fixedChecks):
    discard checked(int64(int32(left)) - int64(int32(right)))
  Fixed(int32(left) -% int32(right))

proc `-`*(value: Fixed): Fixed {.inline.} =
  ## Negates a value. Negating `FixedMinimum` wraps back to itself.
  Fixed(0'i32 -% int32(value))

proc abs*(value: Fixed): Fixed {.inline.} =
  ## Returns the magnitude. The magnitude of `FixedMinimum` wraps to itself.
  if int32(value) < 0: -value else: value

proc `+=`*(left: var Fixed, right: Fixed) {.inline.} =
  ## Adds in place.
  left = left + right

proc `-=`*(left: var Fixed, right: Fixed) {.inline.} =
  ## Subtracts in place.
  left = left - right

## Multiplication and division

proc `*`*(left, right: Fixed): Fixed {.inline.} =
  ## Multiplies through an int64 intermediate, rounding to nearest.
  narrow((int64(int32(left)) * int64(int32(right)) + FixedRounding)
    .ashr(FixedShift))

proc `*`*(left: Fixed, right: int32): Fixed {.inline.} =
  ## Multiplies by a whole number without needing to shift back.
  narrow(int64(int32(left)) * int64(right))

proc `*`*(left: int32, right: Fixed): Fixed {.inline.} =
  ## Multiplies by a whole number without needing to shift back.
  right * left

proc divideRounded(numerator, denominator: int64): int64 {.inline.} =
  ## Divides rounding to nearest with halves going up, for any sign.
  doAssert denominator != 0, "fixed-point division by zero"
  var
    top = numerator
    bottom = denominator
  if bottom < 0:
    top = -top
    bottom = -bottom
  floorDivide(top + bottom div 2, bottom)

proc `/`*(left, right: Fixed): Fixed {.inline.} =
  ## Divides through an int64 intermediate, rounding to nearest.
  narrow(divideRounded(int64(int32(left)) shl FixedShift, int64(int32(right))))

proc `/`*(left: Fixed, right: int32): Fixed {.inline.} =
  ## Divides by a whole number without needing to shift up.
  narrow(divideRounded(int64(int32(left)), int64(right)))

proc multiplyDivide*(left, right, divisor: Fixed): Fixed {.inline.} =
  ## Returns `left * right / divisor` keeping full precision in between.
  narrow(divideRounded(int64(int32(left)) * int64(int32(right)),
    int64(int32(divisor))))

proc floorMod*(left, right: Fixed): Fixed {.inline.} =
  ## Returns the remainder carrying the sign of the right operand.
  doAssert int32(right) != 0, "fixed-point modulo by zero"
  let remainder = int32(left) mod int32(right)
  if remainder != 0 and (remainder < 0) != (int32(right) < 0):
    Fixed(remainder +% int32(right))
  else:
    Fixed(remainder)

## Comparison helpers

proc min*(left, right: Fixed): Fixed {.inline.} =
  ## Returns the smaller of two values.
  if int32(left) < int32(right): left else: right

proc max*(left, right: Fixed): Fixed {.inline.} =
  ## Returns the larger of two values.
  if int32(left) > int32(right): left else: right

proc clamp*(value, lowest, highest: Fixed): Fixed {.inline.} =
  ## Restricts a value to an inclusive range.
  if int32(value) < int32(lowest): lowest
  elif int32(value) > int32(highest): highest
  else: value

proc sign*(value: Fixed): int32 {.inline.} =
  ## Returns -1, 0, or 1 according to the sign.
  if int32(value) < 0: -1'i32
  elif int32(value) > 0: 1'i32
  else: 0'i32

proc lerp*(start, finish, amount: Fixed): Fixed {.inline.} =
  ## Blends between two values, where an amount of one reaches the finish.
  start + (finish - start) * amount

## Roots and lengths

proc integerSqrt*(value: int64): int64 =
  ## Returns the floor square root using deterministic integer arithmetic.
  ##
  ## Newton's method, seeded from the bit length so the first estimate is
  ## already above the answer, which is what makes the descent land exactly on
  ## the floor. Each step roughly doubles the correct digits, so this settles
  ## in a handful of iterations where a digit-by-digit loop needs one per two
  ## bits. There is no floating point anywhere in it.
  if value <= 0:
    return 0
  if value < 4:
    return 1
  let bits = 64 - countLeadingZeroBits(value)
  var root = 1'i64 shl ((bits + 1) shr 1)
  while true:
    let next = (root + value div root) shr 1
    if next >= root:
      break
    root = next
  root

proc sqrt*(value: Fixed): Fixed {.inline.} =
  ## Returns the square root, rounded down. Negative input returns zero.
  ##
  ## Shifting up by the fraction width first turns the input into a 32.32
  ## value, whose integer square root is already a 16.16 result.
  narrow(integerSqrt(int64(int32(value)) shl FixedShift))

proc lengthSquared*(x, y: Fixed): int64 {.inline.} =
  ## Returns the squared length as a 32.32 value, which never overflows here.
  int64(int32(x)) * int64(int32(x)) + int64(int32(y)) * int64(int32(y))

proc hypot*(x, y: Fixed): Fixed {.inline.} =
  ## Returns the planar length of a vector, rounded down.
  ##
  ## The squared length is a 32.32 value, so its integer square root is
  ## already 16.16. Inputs stay exact while their magnitudes are below 23170,
  ## which covers any sane world size.
  narrow(integerSqrt(lengthSquared(x, y)))

## Trigonometry tables

const TableSize = 1024
  ## Samples across a quarter turn. Interpolation error stays near 3e-7.

proc buildSineTable(): array[TableSize + 2, int32] {.compileTime.} =
  ## Samples a quarter of a sine wave, plus guard entries for interpolation.
  for index in 0 .. TableSize + 1:
    let angle = stdMath.PI / 2.0 * (float64(index) / float64(TableSize))
    result[index] = int32(stdMath.round(stdMath.sin(angle) * float64(FixedScale)))

proc buildArctangentTable(): array[TableSize + 2, int32] {.compileTime.} =
  ## Samples the arctangent over zero to one, plus guard entries.
  for index in 0 .. TableSize + 1:
    let ratio = float64(index) / float64(TableSize)
    result[index] =
      int32(stdMath.round(stdMath.arctan(ratio) * float64(FixedScale)))

const
  SineTable* = buildSineTable()
  ArctangentTable* = buildArctangentTable()

## Trigonometry

proc turnPhase(angle: Fixed): uint32 {.inline.} =
  ## Converts radians into a fraction of a turn, wrapping for free.
  ##
  ## The result is a 0.32 value, so the whole turn is exactly the 32-bit
  ## range and angles far outside a single turn need no extra reduction.
  cast[uint32]((int64(int32(angle)) * InverseTau).ashr(FixedShift))

proc sampleQuarter(table: array[TableSize + 2, int32],
    position: uint32): Fixed {.inline.} =
  ## Interpolates a quarter-turn table at a 0.30 position.
  let
    index = int(position shr 20)
    weight = int64((position shr 4) and 0xFFFF'u32)
    lower = int64(table[index])
    upper = int64(table[index + 1])
  Fixed(int32(lower + ((upper - lower) * weight + FixedRounding)
    .ashr(FixedShift)))

proc sinePhase(phase: uint32): Fixed {.inline.} =
  ## Returns the sine of a turn fraction by folding it into one quarter.
  const Quarter = 1'u32 shl 30
  let
    quadrant = phase shr 30
    position = phase and (Quarter - 1)
  case quadrant
  of 0: sampleQuarter(SineTable, position)
  of 1: sampleQuarter(SineTable, Quarter - position)
  of 2: -sampleQuarter(SineTable, position)
  else: -sampleQuarter(SineTable, Quarter - position)

proc sin*(angle: Fixed): Fixed {.inline.} =
  ## Returns the sine of an angle in radians.
  sinePhase(turnPhase(angle))

proc cos*(angle: Fixed): Fixed {.inline.} =
  ## Returns the cosine of an angle in radians.
  sinePhase(turnPhase(angle) + (1'u32 shl 30))

proc tan*(angle: Fixed): Fixed {.inline.} =
  ## Returns the tangent of an angle in radians.
  ##
  ## Near a quarter turn the true value has no representation, so the result
  ## saturates to the extreme of the range instead of dividing by zero.
  let
    phase = turnPhase(angle)
    sine = sinePhase(phase)
    cosine = sinePhase(phase + (1'u32 shl 30))
  if int32(cosine) == 0:
    if int32(sine) < 0: FixedMinimum else: FixedMaximum
  else:
    sine / cosine

proc arctan2*(y, x: Fixed): Fixed =
  ## Returns the angle of a vector in radians, from negative pi to pi.
  let
    verticalMagnitude = int64(int32(abs(y)))
    horizontalMagnitude = int64(int32(abs(x)))
  if verticalMagnitude == 0 and horizontalMagnitude == 0:
    return FixedZero
  let
    steep = verticalMagnitude > horizontalMagnitude
    smaller = if steep: horizontalMagnitude else: verticalMagnitude
    larger = if steep: verticalMagnitude else: horizontalMagnitude
    ratio = uint32(divideRounded(smaller shl FixedShift, larger))
    index = int(ratio shr 6)
    weight = int64((ratio and 0x3F'u32) shl 10)
    lower = int64(ArctangentTable[index])
    upper = int64(ArctangentTable[index + 1])
  var angle = Fixed(int32(lower + ((upper - lower) * weight + FixedRounding)
    .ashr(FixedShift)))
  if steep:
    angle = FixedHalfPi - angle
  if int32(x) < 0:
    angle = FixedPi - angle
  if int32(y) < 0:
    angle = -angle
  angle

## Two-dimensional vectors

proc fixedVec2*(): FixedVec2 {.inline.} =
  ## Builds a vector with both coordinates set to zero.
  FixedVec2Zero

proc fixedVec2*(x, y: Fixed): FixedVec2 {.inline.} =
  ## Builds a vector from two fixed-point coordinates.
  FixedVec2(x: x, y: y)

proc fixedVec2*(value: Fixed): FixedVec2 {.inline.} =
  ## Builds a vector with both coordinates set to the same value.
  FixedVec2(x: value, y: value)

proc fixedVec2*(x, y: int32): FixedVec2 {.inline.} =
  ## Builds a vector from two whole-number coordinates.
  FixedVec2(x: fixed(x), y: fixed(y))

proc `[]`*(vector: FixedVec2, index: int): Fixed {.inline.} =
  ## Returns a coordinate by index, where zero is x and one is y.
  case index
  of 0: vector.x
  of 1: vector.y
  else: raise newException(IndexDefect, "fixed vector index out of bounds")

proc `[]=`*(vector: var FixedVec2, index: int, value: Fixed) {.inline.} =
  ## Sets a coordinate by index, where zero is x and one is y.
  case index
  of 0: vector.x = value
  of 1: vector.y = value
  else: raise newException(IndexDefect, "fixed vector index out of bounds")

proc `==`*(left, right: FixedVec2): bool {.inline.} =
  ## Returns whether both coordinates are equal.
  left.x == right.x and left.y == right.y

proc `!=`*(left, right: FixedVec2): bool {.inline.} =
  ## Returns whether either coordinate is different.
  left.x != right.x or left.y != right.y

proc `+`*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Adds two vectors component by component.
  fixedVec2(left.x + right.x, left.y + right.y)

proc `-`*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Subtracts two vectors component by component.
  fixedVec2(left.x - right.x, left.y - right.y)

proc `-`*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Negates both coordinates.
  fixedVec2(-vector.x, -vector.y)

proc `*`*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Multiplies two vectors component by component.
  fixedVec2(left.x * right.x, left.y * right.y)

proc `*`*(vector: FixedVec2, scalar: Fixed): FixedVec2 {.inline.} =
  ## Multiplies both coordinates by a fixed-point scalar.
  fixedVec2(vector.x * scalar, vector.y * scalar)

proc `*`*(scalar: Fixed, vector: FixedVec2): FixedVec2 {.inline.} =
  ## Multiplies both coordinates by a fixed-point scalar.
  vector * scalar

proc `*`*(vector: FixedVec2, scalar: int32): FixedVec2 {.inline.} =
  ## Multiplies both coordinates by a whole-number scalar.
  fixedVec2(vector.x * scalar, vector.y * scalar)

proc `*`*(scalar: int32, vector: FixedVec2): FixedVec2 {.inline.} =
  ## Multiplies both coordinates by a whole-number scalar.
  vector * scalar

proc `/`*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Divides two vectors component by component.
  fixedVec2(left.x / right.x, left.y / right.y)

proc `/`*(vector: FixedVec2, scalar: Fixed): FixedVec2 {.inline.} =
  ## Divides both coordinates by a fixed-point scalar.
  fixedVec2(vector.x / scalar, vector.y / scalar)

proc `/`*(vector: FixedVec2, scalar: int32): FixedVec2 {.inline.} =
  ## Divides both coordinates by a whole-number scalar.
  fixedVec2(vector.x / scalar, vector.y / scalar)

proc `+=`*(left: var FixedVec2, right: FixedVec2) {.inline.} =
  ## Adds a vector in place.
  left.x += right.x
  left.y += right.y

proc `-=`*(left: var FixedVec2, right: FixedVec2) {.inline.} =
  ## Subtracts a vector in place.
  left.x -= right.x
  left.y -= right.y

proc `*=`*(left: var FixedVec2, right: FixedVec2) {.inline.} =
  ## Multiplies by a vector component by component in place.
  left = left * right

proc `*=`*(vector: var FixedVec2, scalar: Fixed) {.inline.} =
  ## Multiplies by a fixed-point scalar in place.
  vector = vector * scalar

proc `*=`*(vector: var FixedVec2, scalar: int32) {.inline.} =
  ## Multiplies by a whole-number scalar in place.
  vector = vector * scalar

proc `/=`*(left: var FixedVec2, right: FixedVec2) {.inline.} =
  ## Divides by a vector component by component in place.
  left = left / right

proc `/=`*(vector: var FixedVec2, scalar: Fixed) {.inline.} =
  ## Divides by a fixed-point scalar in place.
  vector = vector / scalar

proc `/=`*(vector: var FixedVec2, scalar: int32) {.inline.} =
  ## Divides by a whole-number scalar in place.
  vector = vector / scalar

proc abs*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Returns the component-wise magnitudes.
  fixedVec2(abs(vector.x), abs(vector.y))

proc floor*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Rounds both coordinates down to whole values.
  fixedVec2(floor(vector.x), floor(vector.y))

proc ceil*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Rounds both coordinates up to whole values.
  fixedVec2(ceil(vector.x), ceil(vector.y))

proc round*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Rounds both coordinates to the nearest whole values.
  fixedVec2(round(vector.x), round(vector.y))

proc min*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Returns the component-wise minimum.
  fixedVec2(min(left.x, right.x), min(left.y, right.y))

proc max*(left, right: FixedVec2): FixedVec2 {.inline.} =
  ## Returns the component-wise maximum.
  fixedVec2(max(left.x, right.x), max(left.y, right.y))

proc clamp*(vector, lowest, highest: FixedVec2): FixedVec2 {.inline.} =
  ## Restricts both coordinates to component-wise inclusive ranges.
  fixedVec2(
    clamp(vector.x, lowest.x, highest.x),
    clamp(vector.y, lowest.y, highest.y)
  )

proc clamp*(vector: FixedVec2, lowest, highest: Fixed): FixedVec2 {.inline.} =
  ## Restricts both coordinates to the same inclusive range.
  fixedVec2(
    clamp(vector.x, lowest, highest),
    clamp(vector.y, lowest, highest)
  )

proc lerp*(start, finish: FixedVec2, amount: Fixed): FixedVec2 {.inline.} =
  ## Blends between two vectors using one fixed-point amount.
  start + (finish - start) * amount

proc dot*(left, right: FixedVec2): Fixed {.inline.} =
  ## Returns the scalar dot product.
  left.x * right.x + left.y * right.y

proc cross*(left, right: FixedVec2): Fixed {.inline.} =
  ## Returns the scalar two-dimensional cross product.
  left.x * right.y - left.y * right.x

proc lengthSquared*(vector: FixedVec2): int64 {.inline.} =
  ## Returns the exact squared length as a 32.32 value.
  lengthSquared(vector.x, vector.y)

proc length*(vector: FixedVec2): Fixed {.inline.} =
  ## Returns the vector length, rounded down.
  hypot(vector.x, vector.y)

proc distanceSquared*(start, finish: FixedVec2): int64 {.inline.} =
  ## Returns the exact squared distance as a 32.32 value.
  lengthSquared(finish - start)

proc distance*(start, finish: FixedVec2): Fixed {.inline.} =
  ## Returns the distance between two vectors, rounded down.
  length(finish - start)

proc normalize*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Returns a unit vector, or zero when the input has no direction.
  let magnitude = length(vector)
  if magnitude == FixedZero:
    FixedVec2Zero
  else:
    vector / magnitude

proc perpendicular*(vector: FixedVec2): FixedVec2 {.inline.} =
  ## Returns the vector rotated counterclockwise by a quarter turn.
  fixedVec2(-vector.y, vector.x)

proc rotate*(vector: FixedVec2, angle: Fixed): FixedVec2 {.inline.} =
  ## Rotates a vector counterclockwise by an angle in radians.
  let
    cosine = cos(angle)
    sine = sin(angle)
  fixedVec2(
    vector.x * cosine - vector.y * sine,
    vector.x * sine + vector.y * cosine
  )

proc angle*(vector: FixedVec2): Fixed {.inline.} =
  ## Returns the vector angle in radians, from negative pi to pi.
  arctan2(vector.y, vector.x)

proc direction*(angle: Fixed): FixedVec2 {.inline.} =
  ## Returns a unit vector pointing at an angle in radians.
  fixedVec2(cos(angle), sin(angle))

## Text

proc `$`*(value: Fixed): string =
  ## Formats a value with five decimals, using integer arithmetic only.
  let
    magnitude = abs(int64(int32(value)))
    decimals = ((magnitude and (FixedScale - 1)) * 100_000 +
      FixedScale div 2) div FixedScale
  var digits = $decimals
  while digits.len < 5:
    digits = "0" & digits
  (if int32(value) < 0: "-" else: "") & $(magnitude shr FixedShift) & "." &
    digits

proc `$`*(vector: FixedVec2): string =
  ## Formats a vector as two fixed-point coordinates.
  "fixedVec2(" & $vector.x & ", " & $vector.y & ")"

{.pop.}
