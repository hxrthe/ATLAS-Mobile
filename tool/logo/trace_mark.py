"""Vectorizes assets/images/ATLAS_Mobile_Logo.png into SVG path data."""
from pathlib import Path

import cv2
import numpy as np
import potrace

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "images" / "ATLAS_Mobile_Logo.png"
OUT = Path(__file__).with_name("mark_path.txt")

img = cv2.imread(str(SRC)).astype(np.float32)
b, g, r = img[..., 0], img[..., 1], img[..., 2]
redness = r - (g + b) / 2

# Upscale before thresholding so the traced curves follow the anti-aliased edge.
scale = 4
redness = cv2.resize(redness, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
redness = cv2.GaussianBlur(redness, (0, 0), 2.5)
mask = redness > 60

bm = potrace.Bitmap(mask)
plist = bm.trace(turdsize=400, turnpolicy=potrace.POTRACE_TURNPOLICY_MINORITY,
                 alphamax=1.0, opticurve=True, opttolerance=0.4)


def f(v):
    return f"{v / scale:.2f}".rstrip("0").rstrip(".")


parts = []
xs, ys = [], []
for curve in plist:
    s = curve.start_point
    d = [f"M{f(s.x)} {f(s.y)}"]
    for seg in curve.segments:
        if seg.is_corner:
            d.append(f"L{f(seg.c.x)} {f(seg.c.y)}L{f(seg.end_point.x)} {f(seg.end_point.y)}")
            xs += [seg.c.x, seg.end_point.x]
            ys += [seg.c.y, seg.end_point.y]
        else:
            d.append(f"C{f(seg.c1.x)} {f(seg.c1.y)} {f(seg.c2.x)} {f(seg.c2.y)} "
                     f"{f(seg.end_point.x)} {f(seg.end_point.y)}")
            xs += [seg.end_point.x]
            ys += [seg.end_point.y]
    d.append("Z")
    parts.append("".join(d))

OUT.write_text("".join(parts))
print("curves", len(plist), "bbox",
      min(xs) / scale, min(ys) / scale, max(xs) / scale, max(ys) / scale)
solid = cv2.resize((redness > 150).astype(np.uint8), (1024, 1024)) > 0
print("red (RGB)", np.median(img[solid], axis=0)[::-1])
