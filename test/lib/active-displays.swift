// Prints how many displays CoreGraphics considers ACTIVE, and nothing else.
//
// This is the test suite's own probe, deliberately independent of
// record-dot.swift. Asking the binary under test whether the machine can draw
// would let a broken record-dot answer "no display", turning its own failure
// into a skip. A separate probe cannot do that: when it says a display is
// awake, a red dot test that then fails has really failed.
//
// Active is the state that matters here. A display that is online but asleep
// is not in this list, and no overlay can be shown on it, which is exactly the
// case that used to be reported as two red tests.
//
// Compile (test/lib/active-displays.sh does this):
//   swiftc -O -o <tmp>/active-displays active-displays.swift -framework CoreGraphics

import CoreGraphics

var count: UInt32 = 0
guard CGGetActiveDisplayList(0, nil, &count) == .success else {
    // Could not ask the window server at all. Printing nothing and failing is
    // honest: the caller must not read silence as "no display".
    exit(1)
}
print(count)
