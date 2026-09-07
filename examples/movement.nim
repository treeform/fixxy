import fixxy

let
  position = fixedVec2(1, 2)
  target = fixedVec2(4, 6)
  velocity = normalize(target - position) * 0.25'fx
  next = position + velocity

doAssert distance(position, target) == 5'fx
doAssert abs(next.x - 1.15'fx) <= FixedEpsilon
doAssert abs(next.y - 2.2'fx) <= FixedEpsilon
echo next
