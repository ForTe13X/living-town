"""Pure vector helpers for metre UVs following physical grain, independent of Blender."""

import math


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def unit(v):
    n = math.sqrt(dot(v, v))
    return tuple(x / n for x in v) if n > 1e-12 else (1.0, 0.0, 0.0)


def grain_axis(r):
    if r["kind"] == "CYLINDER":
        return unit([r["b"][i] - r["a"][i] for i in range(3)])
    if r["kind"] == "BOX":
        size = [r["high"][i] - r["low"][i] for i in range(3)]
        axis = (
            2
            if r["label"] in ("Headboard", "Back", "Leg")
            else max(range(3), key=lambda i: size[i])
        )
        return tuple(float(i == axis) for i in range(3))
    return (1.0, 0.0, 0.0)


def basis(normal, grain):
    n = unit(normal)
    g = [grain[i] - dot(n, grain) * n[i] for i in range(3)]
    if dot(g, g) < 1e-12:
        seed = min(
            ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
            key=lambda a: abs(dot(a, n)),
        )
        g = [seed[i] - dot(seed, n) * n[i] for i in range(3)]
    u = unit(g)
    v = unit(cross(n, u))
    return u, v


def project(point, normal, grain):
    u, v = basis(normal, grain)
    return dot(point, u), dot(point, v)
