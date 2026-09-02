// Run: swiftc -o /tmp/gazecheck Sources/Tracker/GazeMath.swift Tests/main.swift && /tmp/gazecheck
assert(GazeMath.clamp01(-3) == 0 && GazeMath.clamp01(3) == 1 && GazeMath.clamp01(0.4) == 0.4)
assert(GazeMath.map(raw: 0.5, center: 0.5, gain: 4) == 0.5)
assert(abs(GazeMath.map(raw: 0.6, center: 0.5, gain: 4) - 0.9) < 1e-9)
assert(abs(GazeMath.map(raw: 0.6, center: 0.5, gain: -4) - 0.1) < 1e-9)
assert(GazeMath.map(raw: 9.0, center: 0.5, gain: 4) == 1.0, "must clamp")
assert(abs(GazeMath.ema(0, 1, alpha: 0.25) - 0.25) < 1e-9)

// Eye 0.2 wide, corners level at y=0.5, in a square image.
let eye = [(x: 0.0, y: 0.5), (x: 0.1, y: 0.56), (x: 0.2, y: 0.5), (x: 0.1, y: 0.44)]
let centred = GazeMath.cornerRelative(pupil: (0.1, 0.5), eye: eye, aspect: 1)!
assert(abs(centred.x) < 1e-9 && abs(centred.y) < 1e-9, "pupil between the corners reads as centred")

let up = GazeMath.cornerRelative(pupil: (0.1, 0.52), eye: eye, aspect: 1)!
assert(abs(up.y - 0.1) < 1e-9, "0.02 above corners in a 0.2-wide eye = 0.1 eye-widths")

let rightward = GazeMath.cornerRelative(pupil: (0.14, 0.5), eye: eye, aspect: 1)!
assert(abs(rightward.x - 0.2) < 1e-9)

// A droopy eyelid must not change the reading — that was the vertical-tracking bug.
let droopy = [(x: 0.0, y: 0.5), (x: 0.1, y: 0.52), (x: 0.2, y: 0.5), (x: 0.1, y: 0.48)]
let same = GazeMath.cornerRelative(pupil: (0.1, 0.52), eye: droopy, aspect: 1)!
assert(abs(same.y - up.y) < 1e-9, "eyelid shape is irrelevant, only the corners matter")

// Aspect correction: in a 2:1 image, x units are half the size of y units.
let wide = GazeMath.cornerRelative(pupil: (0.05, 0.5), eye: eye, aspect: 2)!
assert(abs(wide.x + 0.25) < 1e-9)

assert(GazeMath.cornerRelative(pupil: (0.1, 0.5), eye: [(0.1, 0.5)], aspect: 1) == nil, "too few points")

let open = GazeMath.eyeAspectRatio(eye: eye, aspect: 1)!            // 0.12 tall, 0.2 wide
assert(abs(open - 0.6) < 1e-9)
let shut = GazeMath.eyeAspectRatio(eye: [(0.0, 0.5), (0.1, 0.505), (0.2, 0.5), (0.1, 0.495)], aspect: 1)!
assert(shut < open / 3, "a closed eye must read far lower than an open one")
assert(GazeMath.eyeAspectRatio(eye: [(0.1, 0.5)], aspect: 1) == nil)


assert(GazeMath.deadzone(0.03, threshold: 0.08) == 0, "small head drift is ignored")
assert(GazeMath.deadzone(-0.03, threshold: 0.08) == 0)
assert(abs(GazeMath.deadzone(0.20, threshold: 0.08) - 0.12) < 1e-9, "no jump at the edge")
assert(abs(GazeMath.deadzone(-0.20, threshold: 0.08) + 0.12) < 1e-9)
assert(GazeMath.deadzone(0.08, threshold: 0.08) == 0, "boundary is still inside the zone")

print("GazeMath OK")
