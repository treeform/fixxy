import
  std/[math, strutils, unittest],
  fixxy

proc reference(value: Fixed): float64 =
  ## Returns the exact value of a fixed-point number for comparison.
  float64(int32(value)) / 65536.0

proc within(value: Fixed, expected: float64, steps: float64): bool =
  ## Returns whether a value lands within a number of fixed-point steps.
  abs(reference(value) - expected) <= steps / 65536.0

proc digitByDigitSqrt(value: int64): int64 =
  ## Returns the floor square root the slow, obviously correct way.
  ##
  ## This is the textbook shift-and-subtract root, kept here as the reference
  ## that `integerSqrt` must reproduce exactly. It settles one bit of the
  ## answer per iteration with nothing but compares, adds, and shifts, so
  ## there is no room in it for a rounding or convergence mistake to hide.
  if value <= 0:
    return 0
  var
    remaining = value
    root = 0'i64
    bit = 1'i64 shl 62
  while bit > remaining:
    bit = bit shr 2
  while bit != 0:
    if remaining >= root + bit:
      remaining -= root + bit
      root = (root shr 1) + bit
    else:
      root = root shr 1
    bit = bit shr 2
  root

suite "fixxy":
  test "library errors and vector boundaries":
    for text in ["", "abc", "1.2.3", "40000", "-32769"]:
      expect FixxyError:
        discard parseFixed(text)
    check parseFixed("-32768") == FixedMinimum
    check parseFixed("32767.9999847412109375") == FixedMaximum
    expect ValueError:
      discard parseFixed("invalid")
    var vector = FixedVec2One
    expect IndexDefect:
      discard vector[-1]
    expect IndexDefect:
      vector[2] = FixedZero
    check vector == FixedVec2One
    vector *= 3'i32
    vector *= 2'fx
    vector /= fixedVec2(2, 3)
    vector[1] = -vector[1]
    check vector == fixedVec2(3, -2)

  test "fixed layout, whole parts, and fractions":
    doAssert int32(FixedOne) == 65536
    doAssert int32(FixedHalf) == 32768
    doAssert int32(fixed(3'i32)) == 196608
    doAssert fixed(3'i32).toInt == 3
    doAssert fixed(-3'i32).toInt == -3
    doAssert fixed(0'i32) == FixedZero

    # The high half is the whole part and the low half is the fraction, so
    # negatives floor: -1.5 is -2 plus 0.5.
    doAssert whole(1.5'fx) == 1
    doAssert fraction(1.5'fx) == 0x8000'u16
    doAssert whole(-1.5'fx) == -2
    doAssert fraction(-1.5'fx) == 0x8000'u16
    doAssert fixed(-2'i16, 0x8000'u16) == -1.5'fx
    doAssert fixed(1'i16, 0'u16) == FixedOne

    # Rounding toward zero differs from flooring on negatives.
    doAssert (-1.5'fx).toInt == -1
    doAssert floor(-1.5'fx) == fixed(-2'i32)
    doAssert ceil(-1.5'fx) == fixed(-1'i32)
    doAssert round(-1.5'fx) == fixed(-1'i32)
    doAssert floor(1.5'fx) == FixedOne
    doAssert ceil(1.5'fx) == fixed(2'i32)
    doAssert round(1.5'fx) == fixed(2'i32)
    doAssert round(1.4'fx) == FixedOne
    doAssert floor(fixed(3'i32)) == fixed(3'i32)
    doAssert ceil(fixed(3'i32)) == fixed(3'i32)

  test "fixed literals and text":
    doAssert int32(0.5'fx) == 32768
    doAssert int32(0.25'fx) == 16384
    doAssert int32(2'fx) == 131072
    doAssert int32(-0.5'fx) == -32768
    doAssert parseFixed("1.5") == 1.5'fx
    doAssert parseFixed("+1.5") == 1.5'fx
    doAssert parseFixed("1_000.5") == parseFixed("1000.5")
    # The literal rounds the decimal to the nearest step without using floats.
    doAssert int32(0.1'fx) == 6554
    doAssert 0.1'fx == toFixed(0.1)
    doAssert $1.5'fx == "1.50000"
    doAssert $(-1.5'fx) == "-1.50000"
    doAssert $FixedZero == "0.00000"
    doAssert $fixed(42'i32) == "42.00000"

    var raised = false
    try:
      discard parseFixed("1.2.3")
    except ValueError:
      raised = true
    doAssert raised
    raised = false
    try:
      discard parseFixed("40000.0")
    except ValueError:
      raised = true
    doAssert raised

  test "fixed addition, subtraction, and comparison":
    doAssert 1.5'fx + 2.25'fx == 3.75'fx
    doAssert 1.5'fx - 2.25'fx == -0.75'fx
    doAssert -(1.5'fx) == -1.5'fx
    doAssert abs(-1.5'fx) == 1.5'fx
    doAssert abs(1.5'fx) == 1.5'fx
    doAssert 1.5'fx < 2.0'fx
    doAssert 2.0'fx > 1.5'fx
    doAssert 1.5'fx <= 1.5'fx
    doAssert 1.5'fx != 1.25'fx
    doAssert min(1.5'fx, -2.0'fx) == -2.0'fx
    doAssert max(1.5'fx, -2.0'fx) == 1.5'fx
    doAssert clamp(5.0'fx, 0.0'fx, 1.0'fx) == FixedOne
    doAssert clamp(-5.0'fx, 0.0'fx, 1.0'fx) == FixedZero
    doAssert clamp(0.5'fx, 0.0'fx, 1.0'fx) == FixedHalf
    doAssert sign(-1.5'fx) == -1
    doAssert sign(FixedZero) == 0
    doAssert sign(1.5'fx) == 1

    var total = FixedZero
    total += 1.5'fx
    total -= 0.5'fx
    doAssert total == FixedOne

    # Overflow wraps like int32 rather than raising, so results stay defined.
    # Building with -d:fixedChecks turns the same cases into assertions, so
    # they are only exercised in a normal build.
    doAssert -FixedMinimum == FixedMinimum
    doAssert abs(FixedMinimum) == FixedMinimum
    when not defined(fixedChecks):
      doAssert FixedMaximum + FixedEpsilon == FixedMinimum
      doAssert FixedMinimum - FixedEpsilon == FixedMaximum
      doAssert FixedMaximum * fixed(2'i32) == -FixedEpsilon * fixed(2'i32)
    else:
      var caught = false
      try:
        discard FixedMaximum + FixedEpsilon
      except AssertionDefect:
        caught = true
      doAssert caught, "-d:fixedChecks should catch overflow"

  test "fixed multiplication and division":
    doAssert 1.5'fx * 2.0'fx == 3.0'fx
    doAssert 1.5'fx * FixedOne == 1.5'fx
    doAssert -1.5'fx * 2.0'fx == -3.0'fx
    doAssert -1.5'fx * -2.0'fx == 3.0'fx
    doAssert 0.5'fx * 0.5'fx == 0.25'fx
    doAssert 1.5'fx * 4'i32 == 6.0'fx
    doAssert 4'i32 * 1.5'fx == 6.0'fx

    doAssert 3.0'fx / 2.0'fx == 1.5'fx
    doAssert 1.5'fx / FixedOne == 1.5'fx
    doAssert 1.5'fx / 1.5'fx == FixedOne
    doAssert -3.0'fx / 2.0'fx == -1.5'fx
    doAssert 3.0'fx / -2.0'fx == -1.5'fx
    doAssert -3.0'fx / -2.0'fx == 1.5'fx
    doAssert 6.0'fx / 4'i32 == 1.5'fx
    doAssert -6.0'fx / 4'i32 == -1.5'fx

    # Rounding is to nearest with halves going up, in both signs. One third of
    # a step lands below a half step and rounds away; two thirds rounds up.
    doAssert Fixed(3) * FixedHalf == Fixed(2)
    doAssert Fixed(1) * FixedHalf == Fixed(1)
    doAssert Fixed(-3) * FixedHalf == Fixed(-1)
    doAssert Fixed(-1) * FixedHalf == Fixed(0)
    doAssert Fixed(3) / fixed(2'i32) == Fixed(2)
    doAssert Fixed(-3) / fixed(2'i32) == Fixed(-1)

    # An arithmetic shift is what keeps negatives correct. A logical shift
    # would turn this product into a large positive number.
    doAssert int32(-0.5'fx * 0.5'fx) == -16384
    doAssert -0.5'fx * 0.5'fx < FixedZero

    doAssert multiplyDivide(3.0'fx, 4.0'fx, 2.0'fx) == 6.0'fx
    # Full precision in between: the halfway product would overflow if the
    # multiply were narrowed to 16.16 before the divide.
    doAssert multiplyDivide(20000.0'fx, 20000.0'fx, 20000.0'fx) == 20000.0'fx

    doAssert floorMod(5.5'fx, 2.0'fx) == 1.5'fx
    doAssert floorMod(-5.5'fx, 2.0'fx) == 0.5'fx
    doAssert floorMod(5.5'fx, -2.0'fx) == -0.5'fx

    doAssert lerp(0.0'fx, 10.0'fx, FixedZero) == FixedZero
    doAssert lerp(0.0'fx, 10.0'fx, FixedOne) == 10.0'fx
    doAssert lerp(0.0'fx, 10.0'fx, FixedHalf) == 5.0'fx
    doAssert lerp(-4.0'fx, 4.0'fx, FixedHalf) == FixedZero

  test "integer square roots against the textbook algorithm":
    # `integerSqrt` uses Newton's method for speed. It must agree with the
    # digit-by-digit root on every input, not merely to within a step, or the
    # replay hashes it feeds would move.
    doAssert integerSqrt(0) == 0
    doAssert integerSqrt(-1) == 0
    doAssert integerSqrt(low(int64)) == 0
    for value in 0'i64 .. 5000'i64:
      doAssert integerSqrt(value) == digitByDigitSqrt(value), $value

    # Perfect squares and their neighbours are where an off-by-one would show.
    for root in 1'i64 .. 3000'i64:
      let square = root * root
      doAssert integerSqrt(square) == root, $square
      doAssert integerSqrt(square - 1) == root - 1, $square
      doAssert integerSqrt(square + 1) == root, $square

    # Every power-of-two boundary across the full 64-bit signed range, which
    # covers both `sqrt` at 32.32 and `lengthSquared` at its widest.
    for shift in 0 .. 62:
      for delta in -2'i64 .. 2'i64:
        let value = (1'i64 shl shift) + delta
        doAssert integerSqrt(value) == digitByDigitSqrt(value), $value

    # A scattered sweep over every magnitude, including values far above the
    # fixed-point range. The state is unsigned so the generator wraps by
    # definition rather than tripping an overflow check.
    var state = 1'u64
    for step in 0 ..< 20000:
      state = state * 6364136223846793005'u64 + 1442695040888963407'u64
      let sample = int64(state shr (1 + (step mod 40)))
      doAssert integerSqrt(sample) == digitByDigitSqrt(sample), $sample

  test "fixed square roots and lengths":
    doAssert sqrt(FixedZero) == FixedZero
    doAssert sqrt(-4.0'fx) == FixedZero
    doAssert sqrt(FixedOne) == FixedOne
    doAssert sqrt(4.0'fx) == 2.0'fx
    doAssert sqrt(9.0'fx) == 3.0'fx
    doAssert sqrt(0.25'fx) == FixedHalf
    doAssert sqrt(2.0'fx).within(sqrt(2.0), 1.0)

    # Squaring the root returns the input to within the rounding of a floor.
    for step in 1 .. 400:
      let value = fixed(int32(step)) / 4'i32
      let root = sqrt(value)
      doAssert root * root <= value
      doAssert (root + FixedEpsilon) * (root + FixedEpsilon) >= value

    doAssert hypot(3.0'fx, 4.0'fx) == 5.0'fx
    doAssert hypot(-3.0'fx, -4.0'fx) == 5.0'fx
    doAssert hypot(FixedZero, FixedZero) == FixedZero
    doAssert hypot(FixedOne, FixedOne).within(sqrt(2.0), 1.0)
    doAssert lengthSquared(3.0'fx, 4.0'fx) == 25'i64 shl 32
    # Well past the world extent of 64 units, still exact.
    doAssert hypot(20000.0'fx, 0.0'fx) == 20000.0'fx

  test "fixed two-dimensional vectors":
    let
      left = fixedVec2(1.5'fx, -2.0'fx)
      right = fixedVec2(0.5'fx, 3.0'fx)
    doAssert sizeof(FixedVec2) == 8
    doAssert fixedVec2() == FixedVec2Zero
    doAssert fixedVec2(FixedOne) == FixedVec2One
    doAssert fixedVec2(2, -3) == fixedVec2(2.0'fx, -3.0'fx)
    doAssert left[0] == 1.5'fx
    doAssert left[1] == -2.0'fx
    doAssert left + right == fixedVec2(2.0'fx, 1.0'fx)
    doAssert left - right == fixedVec2(1.0'fx, -5.0'fx)
    doAssert -left == fixedVec2(-1.5'fx, 2.0'fx)
    doAssert left * right == fixedVec2(0.75'fx, -6.0'fx)
    doAssert left * 2.0'fx == fixedVec2(3.0'fx, -4.0'fx)
    doAssert 2.0'fx * left == fixedVec2(3.0'fx, -4.0'fx)
    doAssert left * 2'i32 == fixedVec2(3.0'fx, -4.0'fx)
    doAssert 2'i32 * left == fixedVec2(3.0'fx, -4.0'fx)
    doAssert left / fixedVec2(0.5'fx, 2.0'fx) ==
      fixedVec2(3.0'fx, -1.0'fx)
    doAssert left / 0.5'fx == fixedVec2(3.0'fx, -4.0'fx)
    doAssert left / 2'i32 == fixedVec2(0.75'fx, -1.0'fx)

    var changed = left
    changed[0] = 2.0'fx
    changed += right
    changed -= fixedVec2(0.5'fx, 1.0'fx)
    changed *= fixedVec2(2.0'fx, 0.5'fx)
    changed /= 0.5'fx
    changed /= 2'i32
    doAssert changed == fixedVec2(4.0'fx, 0.0'fx)

    doAssert abs(left) == fixedVec2(1.5'fx, 2.0'fx)
    doAssert floor(left) == fixedVec2(1.0'fx, -2.0'fx)
    doAssert ceil(left) == fixedVec2(2.0'fx, -2.0'fx)
    doAssert round(left) == fixedVec2(2.0'fx, -2.0'fx)
    doAssert min(left, right) == fixedVec2(0.5'fx, -2.0'fx)
    doAssert max(left, right) == fixedVec2(1.5'fx, 3.0'fx)
    doAssert clamp(left, FixedVec2Zero, FixedVec2One) ==
      fixedVec2(1.0'fx, 0.0'fx)
    doAssert clamp(left, -1.0'fx, 1.0'fx) ==
      fixedVec2(1.0'fx, -1.0'fx)
    doAssert lerp(left, right, FixedHalf) ==
      fixedVec2(1.0'fx, 0.5'fx)

    let vector = fixedVec2(3.0'fx, 4.0'fx)
    doAssert dot(vector, fixedVec2(2.0'fx, -1.0'fx)) == 2.0'fx
    doAssert cross(vector, fixedVec2(2.0'fx, -1.0'fx)) == -11.0'fx
    doAssert lengthSquared(vector) == 25'i64 shl 32
    doAssert length(vector) == 5.0'fx
    doAssert distance(FixedVec2Zero, vector) == 5.0'fx
    doAssert distanceSquared(FixedVec2Zero, vector) == 25'i64 shl 32
    doAssert normalize(FixedVec2Zero) == FixedVec2Zero
    let unit = normalize(vector)
    doAssert unit.x.within(0.6, 1.0)
    doAssert unit.y.within(0.8, 1.0)
    doAssert perpendicular(vector) == fixedVec2(-4.0'fx, 3.0'fx)
    doAssert rotate(fixedVec2(1.0'fx, 0.0'fx), FixedHalfPi).x
      .within(0.0, 1.0)
    doAssert rotate(fixedVec2(1.0'fx, 0.0'fx), FixedHalfPi).y
      .within(1.0, 1.0)
    doAssert angle(fixedVec2(1.0'fx, 1.0'fx)).within(PI / 4.0, 4.0)
    doAssert direction(FixedHalfPi).x.within(0.0, 1.0)
    doAssert direction(FixedHalfPi).y == FixedOne
    doAssert $left == "fixedVec2(1.50000, -2.00000)"

  test "fixed trigonometry":
    doAssert sin(FixedZero) == FixedZero
    doAssert sin(FixedHalfPi) == FixedOne
    doAssert cos(FixedZero) == FixedOne
    doAssert sin(FixedPi).within(0.0, 2.0)
    doAssert cos(FixedPi).within(-1.0, 2.0)
    doAssert sin(-FixedHalfPi).within(-1.0, 2.0)
    doAssert cos(FixedHalfPi).within(0.0, 2.0)

    # Range reduction is free, so angles far outside one turn still work.
    doAssert sin(FixedHalfPi + FixedTau * 20'i32).within(1.0, 4.0)
    doAssert sin(FixedHalfPi - FixedTau * 20'i32).within(1.0, 4.0)
    # A hundred turns is limited by the angle, not by the sine. `FixedTau`
    # stores 411775 where the exact value is 411774.83, so a hundred of them do
    # not land on a whole number of turns. Measured against the angle actually
    # given, the sine is still right to a fraction of a step.
    let farAngle = FixedTau * 100'i32
    doAssert sin(farAngle).within(sin(reference(farAngle)), 1.0)
    doAssert cos(farAngle).within(cos(reference(farAngle)), 1.0)
    # Wrapping by tau first collapses that excess rather than carrying it, so
    # simulation angles should be kept wrapped rather than allowed to grow.
    doAssert floorMod(farAngle, FixedTau) == FixedZero
    doAssert sin(floorMod(farAngle, FixedTau)) == FixedZero

    # The circle identity holds all the way around.
    for step in 0 ..< 720:
      let angle = FixedTau * int32(step) / 720'i32
      let unit = sin(angle) * sin(angle) + cos(angle) * cos(angle)
      doAssert unit.within(1.0, 4.0)

    doAssert tan(FixedZero) == FixedZero
    doAssert tan(FixedPi / 4'i32).within(1.0, 4.0)
    # A quarter turn has no representable tangent, so it saturates.
    doAssert tan(FixedHalfPi) == FixedMaximum

  test "fixed arctangent":
    doAssert arctan2(FixedZero, FixedZero) == FixedZero
    doAssert arctan2(FixedZero, FixedOne) == FixedZero
    doAssert arctan2(FixedOne, FixedOne).within(PI / 4.0, 4.0)
    doAssert arctan2(FixedOne, FixedZero).within(PI / 2.0, 4.0)
    doAssert arctan2(-FixedOne, FixedZero).within(-PI / 2.0, 4.0)
    doAssert arctan2(FixedZero, -FixedOne).within(PI, 4.0)
    doAssert arctan2(FixedOne, -FixedOne).within(3.0 * PI / 4.0, 4.0)
    doAssert arctan2(-FixedOne, -FixedOne).within(-3.0 * PI / 4.0, 4.0)
    doAssert arctan2(-FixedOne, FixedOne).within(-PI / 4.0, 4.0)

    # Feeding a unit vector back through arctangent recovers its angle.
    for step in 0 ..< 360:
      let angle = FixedPi * 2'i32 * int32(step) / 360'i32 - FixedPi
      if angle <= -FixedPi or angle >= FixedPi:
        continue
      let recovered = arctan2(sin(angle), cos(angle))
      doAssert (recovered - angle).within(0.0, 8.0)

  test "fixed accuracy against a reference":
    var
      worstSine = 0.0
      worstCosine = 0.0
      worstArctangent = 0.0
      worstRoot = 0.0
    for step in 0 ..< 4096:
      let
        exact = -PI + 2.0 * PI * float64(step) / 4096.0
        angle = toFixed(exact)
      worstSine = max(worstSine, abs(reference(sin(angle)) - sin(exact)))
      worstCosine = max(worstCosine, abs(reference(cos(angle)) - cos(exact)))
      # Angles are compared the long way around, since arctangent reports a
      # half turn as positive pi while the sweep starts at negative pi.
      var difference =
        reference(arctan2(toFixed(sin(exact)), toFixed(cos(exact)))) - exact
      if difference > PI:
        difference -= 2.0 * PI
      elif difference < -PI:
        difference += 2.0 * PI
      worstArctangent = max(worstArctangent, abs(difference))
    for step in 1 ..< 4096:
      let exact = float64(step) / 16.0
      worstRoot = max(worstRoot, abs(reference(sqrt(toFixed(exact))) -
        sqrt(exact)))

    # Every function stays within a few steps of the true value. A step is
    # 1/65536, about 0.0000153.
    doAssert worstSine < 4.0 / 65536.0, $worstSine
    doAssert worstCosine < 4.0 / 65536.0, $worstCosine
    doAssert worstArctangent < 8.0 / 65536.0, $worstArctangent
    doAssert worstRoot < 2.0 / 65536.0, $worstRoot

  test "fixed table stability":
    # The tables are generated by the compiler's own float math. Pinning a few
    # entries makes any drift between toolchains fail here loudly, instead of
    # silently desynchronizing a replay.
    doAssert SineTable[0] == 0
    doAssert SineTable[1] == 101
    doAssert SineTable[256] == 25080
    doAssert SineTable[512] == 46341
    doAssert SineTable[768] == 60547
    doAssert SineTable[1024] == 65536
    doAssert ArctangentTable[0] == 0
    doAssert ArctangentTable[256] == 16055
    doAssert ArctangentTable[512] == 30386
    doAssert ArctangentTable[1024] == 51472

  test "fixed determinism":
    # A fixed sequence of operations hashed to an exact value. Any change to
    # rounding, shifting, or table contents moves this number, which is the
    # property replays depend on.
    var
      hash = 0xcbf29ce484222325'u64
      value = 0.125'fx
    for step in 1 .. 2000:
      value = value * 1.01'fx + FixedEpsilon
      value = value + sin(FixedTau * int32(step) / 97'i32) / 8'i32
      value = value - sqrt(abs(value)) / 4'i32
      value = value + arctan2(cos(value), FixedOne) / 16'i32
      value = floorMod(value, 64.0'fx)
      hash = (hash xor uint64(cast[uint32](int32(value)))) * 0x100000001b3'u64
    doAssert value == Fixed(3814779), $int32(value)
    doAssert hash == 0xabb5ef4c286eab4f'u64, "0x" & toHex(hash)
