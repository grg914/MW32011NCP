#!/usr/bin/env python3
"""CPU reference test for the draft HDR10 compute shader's math.

No game/DLL/GPU access. Validates nominal ST 2084/PQ transfer and
Rec.709 -> BT.2020 primary conversion using a separately written,
scalar implementation, to catch shader coefficient transposition.
"""
from math import isclose

M1 = 2610 / 16384
M2 = 2523 / 32
C1 = 3424 / 4096
C2 = 2413 / 128
C3 = 2392 / 128


def pq(nits: float) -> float:
    y = max(0.0, min(nits / 10000, 1.0)) ** M1
    return ((C1 + C2 * y) / (1 + C3 * y)) ** M2


def rec709_to_bt2020(rgb):
    r, g, b = rgb
    return (
        0.6274040 * r + 0.3292820 * g + 0.0433136 * b,
        0.0690970 * r + 0.9195400 * g + 0.0113612 * b,
        0.0163916 * r + 0.0880132 * g + 0.8955950 * b,
    )


def test():
    anchors = {
        0.0: 7.309559025783966e-07,
        100.0: 0.508078421517399,
        1000.0: 0.751827096247041,
        10000.0: 1.0,
    }
    for nits, expected in anchors.items():
        assert isclose(pq(nits), expected, rel_tol=0.0, abs_tol=2e-8), (
            f"PQ {nits} nit: {pq(nits)} != {expected}"
        )

    values = [pq(v) for v in (0, 10, 100, 203, 400, 1000, 4000, 10000)]
    assert all(a < b for a, b in zip(values, values[1:])), "PQ must be monotonic"

    white = rec709_to_bt2020((1.0, 1.0, 1.0))
    for channel in white:
        assert isclose(channel, 1.0, abs_tol=5e-5), (
            f"Rec.709 white should remain D65 BT.2020 white: {white}"
        )
    assert rec709_to_bt2020((1.0, 0.0, 0.0)) == (
        0.6274040, 0.0690970, 0.0163916
    )
    assert rec709_to_bt2020((0.0, 1.0, 0.0)) == (
        0.3292820, 0.9195400, 0.0880132
    )
    assert rec709_to_bt2020((0.0, 0.0, 1.0)) == (
        0.0433136, 0.0113612, 0.8955950
    )

    print("PASS: HDR10 PQ transfer and Rec.709->BT.2020 primaries")


if __name__ == "__main__":
    test()
