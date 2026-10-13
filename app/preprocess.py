import numpy as np

GRID = 32
BLOCK = 4
PIXEL_MAX = 15
INK_TARGET = 313
MIN_RADIUS = 1.0
MAX_RADIUS = 6.0
SYNC = 0x80


def normalize(strokes, pen_radius):
    points = np.array([p for s in strokes for p in s], dtype=float)
    lo, hi = points.min(0), points.max(0)
    size = hi - lo
    room = GRID - 2 * pen_radius
    scale = room / max(size[1], size[0], 1e-9)
    center = (lo + hi) / 2
    return [[(GRID / 2 + (x - center[0]) * scale, GRID / 2 + (y - center[1]) * scale)
             for x, y in s] for s in strokes]


def distances(strokes):
    yy, xx = np.mgrid[0:GRID, 0:GRID] + 0.5
    centers = np.stack([xx.ravel(), yy.ravel()], 1)
    best = np.full(GRID * GRID, np.inf)
    for s in strokes:
        pts = np.array(s, dtype=float)
        if len(pts) == 1:
            pts = np.vstack([pts, pts])
        a, b = pts[:-1], pts[1:]
        ab = b - a
        length2 = np.maximum((ab ** 2).sum(1), 1e-12)
        t = ((centers[:, None, :] - a[None]) * ab[None]).sum(2) / length2[None]
        nearest = a[None] + np.clip(t, 0, 1)[..., None] * ab[None]
        best = np.minimum(best, ((centers[:, None, :] - nearest) ** 2).sum(2).min(1))
    return np.sqrt(best).reshape(GRID, GRID)


def ink_radius(dist, target=INK_TARGET):
    r = np.sort(dist.ravel())[target - 1]
    return float(np.clip(r, MIN_RADIUS, MAX_RADIUS))


def draw(strokes, target=INK_TARGET):
    radius = 2.0
    for _ in range(4):
        dist = distances(normalize(strokes, radius))
        radius = ink_radius(dist, target)
    dist = distances(normalize(strokes, radius))
    return dist <= radius


def to_pixels(bitmap):
    counts = bitmap.reshape(8, BLOCK, 8, BLOCK).sum((1, 3))
    return np.minimum(counts, PIXEL_MAX).astype(np.int64).ravel()


def strokes_to_pixels(strokes, target=INK_TARGET):
    if not any(len(s) for s in strokes):
        bitmap = np.zeros((GRID, GRID), dtype=bool)
    else:
        bitmap = draw([s for s in strokes if len(s)], target)
    return to_pixels(bitmap), bitmap


def frame_bytes(pixels):
    return bytes([SYNC] + [int(p) for p in pixels])
