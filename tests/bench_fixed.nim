import
  std/math,
  benchy,
  fixxy

const Runs {.intdefine.} = 4096
  ## Operations per timed iteration.

var
  fixedInputs: array[Runs, Fixed]
  floatInputs: array[Runs, float32]
  fixedSink: Fixed
  floatSink: float32

for index in 0 ..< Runs:
  # A spread of values across a plausible world extent, avoiding zero so the
  # division benchmarks stay meaningful.
  let value = 0.75 + float64(index) * 63.0 / float64(Runs)
  fixedInputs[index] = toFixed(value)
  floatInputs[index] = float32(value)

echo "Comparing Q16.16 fixed point against float32, ", Runs, " operations each"

timeIt "fixed add":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + fixedInputs[index]
  fixedSink = total

timeIt "float add":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + floatInputs[index]
  floatSink = total

timeIt "fixed multiply":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + fixedInputs[index] * 0.5'fx
  fixedSink = total

timeIt "float multiply":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + floatInputs[index] * 0.5'f32
  floatSink = total

timeIt "fixed divide":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + FixedOne / fixedInputs[index]
  fixedSink = total

timeIt "float divide":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + 1'f32 / floatInputs[index]
  floatSink = total

timeIt "fixed sqrt":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + sqrt(fixedInputs[index])
  fixedSink = total

timeIt "float sqrt":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + sqrt(floatInputs[index])
  floatSink = total

timeIt "fixed hypot":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + hypot(fixedInputs[index], 3.0'fx)
  fixedSink = total

timeIt "float hypot":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + hypot(floatInputs[index], 3'f32)
  floatSink = total

timeIt "fixed sin":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + sin(fixedInputs[index])
  fixedSink = total

timeIt "float sin":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + sin(floatInputs[index])
  floatSink = total

timeIt "fixed arctan2":
  var total = FixedZero
  for index in 0 ..< Runs:
    total = total + arctan2(fixedInputs[index], 3.0'fx)
  fixedSink = total

timeIt "float arctan2":
  var total = 0'f32
  for index in 0 ..< Runs:
    total = total + arctan2(floatInputs[index], 3'f32)
  floatSink = total

## The loops above are uniform enough that the compiler can widen them into
## vector instructions, and it does so differently for each side, so they
## measure throughput rather than what a simulation tick actually feels. The
## pair below is a serial dependency chain that neither side can widen, which
## is closer to per-entity gameplay code.

timeIt "fixed dependent chain":
  var total = FixedOne
  for index in 0 ..< Runs:
    total = total * 0.5'fx + fixedInputs[index]
  fixedSink = total

timeIt "float dependent chain":
  var total = 1'f32
  for index in 0 ..< Runs:
    total = total * 0.5'f32 + floatInputs[index]
  floatSink = total

## A movement step, the shape `movementStep` uses in the game: normalize a
## direction and scale it to one tick of travel.

timeIt "fixed movement step":
  var total = FixedZero
  for index in 0 ..< Runs:
    let
      x = fixedInputs[index]
      y = fixedInputs[Runs - 1 - index]
      distance = hypot(x, y)
    total = total + multiplyDivide(x, 0.05'fx, distance)
  fixedSink = total

timeIt "float movement step":
  var total = 0'f32
  for index in 0 ..< Runs:
    let
      x = floatInputs[index]
      y = floatInputs[Runs - 1 - index]
      distance = hypot(x, y)
    total = total + x * 0.05'f32 / distance
  floatSink = total

echo "Sinks: ", fixedSink, " ", floatSink
