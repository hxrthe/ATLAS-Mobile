"""
High-accuracy OMR core (ArUco 0–3 → 300 DPI warp → inner-core fill → z-score).

Used by Django BubbleSheetScannerService and the ATLAS Mobile Python sidecar.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger(__name__)

try:
    import cv2
    import numpy as np

    _CV = True
except ImportError:
    _CV = False
    np = None  # type: ignore

TARGET_DPI = 300.0
ARUCO_DICT_NAME = "DICT_4X4_50"
# OpenCV IDs → sheet corners
ARUCO_ID_TO_CORNER = {0: "TL", 1: "TR", 2: "BR", 3: "BL"}
INNER_FILL_RATIO = 0.62
MARK_FLOOR = 0.18
BLANK_CEILING = 0.12
ZSCORE_MARK = 1.2
GAP_MARK = 0.10
DOUBLE_GAP = 0.08
MATCH_TEMPLATE_MIN = 0.55
SEARCH_WINDOW_MM = 6.0
CLAHE_CLIP = 2.0
ILLUM_KERNEL = 31
ADAPTIVE_BLOCK = 11
ADAPTIVE_C = 10
ID_FIRST_ROW_OFFSET_MM = 2.5
ID_LABELS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]


@dataclass
class BubbleReading:
    item_number: int
    detected_answer: str
    fill_ratio: float
    second_fill_ratio: float = 0.0
    is_ambiguous: bool = False
    is_confirmed: bool = False
    confidence_note: str = ""

    def to_dict(self) -> dict:
        return self.__dict__.copy()


@dataclass
class OmrCoreResult:
    student_identifier: Optional[str]
    responses: dict
    readings: list
    correct_count: int = 0
    max_score: int = 0
    score_percent: float = 0.0
    is_flagged: bool = False
    flag_reason: Optional[str] = None
    flagged_items: list = field(default_factory=list)
    assessment_id: Optional[str] = None
    alignment: str = "direct"
    low_confidence: bool = False

    def to_dict(self) -> dict:
        d = self.__dict__.copy()
        d["readings"] = [
            r.to_dict() if hasattr(r, "to_dict") else r for r in self.readings
        ]
        return d


def mm_to_px(mm: float, dpi: float) -> int:
    return int(round(mm * dpi / 25.4))


def _aruco_detector():
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    params = cv2.aruco.DetectorParameters()
    try:
        params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    except Exception:
        pass
    return cv2.aruco.ArucoDetector(dictionary, params)


def detect_aruco_centers(gray: np.ndarray) -> dict[int, tuple[float, float]]:
    """Return {id: (cx, cy)} for IDs 0–3 when found."""
    detector = _aruco_detector()
    found: dict[int, tuple[float, float]] = {}

    def _run(img) -> None:
        corners, ids, _ = detector.detectMarkers(img)
        if ids is None:
            return
        for pts, mid in zip(corners, ids.flatten()):
            i = int(mid)
            if i not in ARUCO_ID_TO_CORNER:
                continue
            quad = pts[0]
            found[i] = (float(quad[:, 0].mean()), float(quad[:, 1].mean()))

    _run(gray)
    if len(found) < 4:
        clahe = cv2.createCLAHE(CLAHE_CLIP, (8, 8))
        _run(clahe.apply(gray))
    if len(found) < 4:
        up = cv2.resize(gray, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
        extra: dict[int, tuple[float, float]] = {}
        corners, ids, _ = detector.detectMarkers(up)
        if ids is not None:
            for pts, mid in zip(corners, ids.flatten()):
                i = int(mid)
                if i not in ARUCO_ID_TO_CORNER or i in found:
                    continue
                quad = pts[0] / 1.5
                extra[i] = (float(quad[:, 0].mean()), float(quad[:, 1].mean()))
        found.update(extra)
    return found


def detect_page_quad(gray: np.ndarray) -> Optional[np.ndarray]:
    h, w = gray.shape[:2]
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edged = cv2.Canny(blurred, 75, 200)
    contours, _ = cv2.findContours(edged, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    for cnt in contours[:12]:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        if len(approx) != 4:
            continue
        pts = approx.reshape(4, 2).astype(np.float32)
        area = cv2.contourArea(pts)
        if 0.10 <= area / (w * h) <= 0.98:
            return _order_points(pts)
    return None


def _order_points(pts: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype=np.float32)
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def _fiducial_centers_px(layout: dict, dpi: float) -> dict[str, tuple[float, float]]:
    out: dict[str, tuple[float, float]] = {}
    fids = layout.get("fiducials") or []
    for f in fids:
        wmm = float(f.get("w_mm") or f.get("size_mm") or 15.0)
        hmm = float(f.get("h_mm") or f.get("size_mm") or 15.0)
        cx = (float(f["x_mm"]) + wmm / 2.0) * dpi / 25.4
        cy = (float(f["y_spec_mm"]) + hmm / 2.0) * dpi / 25.4
        corner = f.get("corner")
        if not corner:
            aid = f.get("id")
            corner = ARUCO_ID_TO_CORNER.get(int(aid)) if aid is not None else None
        if corner:
            out[corner] = (cx, cy)
    return out


def _page_size_px(layout: dict, dpi: float) -> tuple[int, int]:
    page_w_pt = float(layout.get("page_width_pt", 612.0))
    page_h_pt = float(layout.get("page_height_pt", 936.0))
    out_w = max(200, int(round((page_w_pt / 72.0) * dpi)))
    out_h = max(200, int(round((page_h_pt / 72.0) * dpi)))
    return out_w, out_h


def warp_to_page(src: np.ndarray, src_pts: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    dst = np.array(
        [[0, 0], [out_w - 1, 0], [out_w - 1, out_h - 1], [0, out_h - 1]],
        dtype=np.float32,
    )
    M = cv2.getPerspectiveTransform(src_pts.astype(np.float32), dst)
    return cv2.warpPerspective(src, M, (out_w, out_h))


def flatten_illumination(gray: np.ndarray) -> np.ndarray:
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ILLUM_KERNEL, ILLUM_KERNEL))
    illum = cv2.dilate(gray, k)
    illum = np.maximum(illum, 1)
    flat = cv2.divide(gray, illum, scale=255)
    clahe = cv2.createCLAHE(CLAHE_CLIP, (8, 8))
    return clahe.apply(flat)


def adaptive_binary_inv(gray: np.ndarray) -> np.ndarray:
    block = ADAPTIVE_BLOCK if ADAPTIVE_BLOCK % 2 == 1 else ADAPTIVE_BLOCK + 1
    return cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        block,
        ADAPTIVE_C,
    )


def _ring_template(r_px: int) -> np.ndarray:
    size = max(9, r_px * 2 + 5)
    t = np.full((size, size), 255, np.uint8)
    c = size // 2
    thickness = max(1, r_px // 8)
    cv2.circle(t, (c, c), r_px, 0, thickness)
    return t


def snap_bubble(
    gray: np.ndarray, cx: int, cy: int, r_px: int, dpi: float = TARGET_DPI
) -> tuple[int, int, float]:
    tmpl = _ring_template(r_px)
    th, tw = tmpl.shape
    search = max(r_px, mm_to_px(SEARCH_WINDOW_MM, dpi))
    h, w = gray.shape[:2]
    x0 = max(0, cx - search)
    y0 = max(0, cy - search)
    x1 = min(w, cx + search + tw)
    y1 = min(h, cy + search + th)
    roi = gray[y0:y1, x0:x1]
    if roi.shape[0] < th or roi.shape[1] < tw:
        return cx, cy, 0.0
    res = cv2.matchTemplate(roi, tmpl, cv2.TM_CCOEFF_NORMED)
    _, max_v, _, max_l = cv2.minMaxLoc(res)
    if max_v < MATCH_TEMPLATE_MIN:
        return cx, cy, float(max_v)
    nx = x0 + max_l[0] + tw // 2
    ny = y0 + max_l[1] + th // 2
    return int(nx), int(ny), float(max_v)


def inner_fill(binary: np.ndarray, cx: int, cy: int, r_px: int, inner: float = INNER_FILL_RATIO) -> float:
    rr = max(3, int(round(r_px * inner)))
    mask = np.zeros(binary.shape, np.uint8)
    cv2.circle(mask, (int(cx), int(cy)), rr, 255, -1)
    area = int(cv2.countNonZero(mask))
    if area == 0:
        return 0.0
    return float(cv2.countNonZero(cv2.bitwise_and(binary, mask))) / area


def classify_fills(fills: dict[str, float]) -> tuple[str, bool, str]:
    """Return (choice_or_?, ambiguous, note)."""
    if not fills:
        return "?", True, "No choices"
    items = sorted(fills.items(), key=lambda x: x[1], reverse=True)
    best_k, best = items[0]
    second = items[1][1] if len(items) > 1 else 0.0
    vals = np.array([v for _, v in items], dtype=np.float64)
    mean = float(vals.mean())
    std = max(float(vals.std()), 0.02)
    z_best = (best - mean) / std
    gap = best - second
    blank = best < BLANK_CEILING
    marked = best >= MARK_FLOOR and (z_best >= ZSCORE_MARK or gap >= GAP_MARK)
    double = len(items) > 1 and second >= MARK_FLOOR and gap < DOUBLE_GAP
    if blank:
        return "?", True, f"Blank ({best:.2f})"
    if double:
        return "?", True, f"Double mark ({best_k}={best:.2f} vs {second:.2f})"
    if not marked:
        return "?", True, f"Ambiguous ({best_k}={best:.2f} z={z_best:.2f} gap={gap:.2f})"
    return best_k, False, f"Marked {best_k} ({best:.2f})"


def _calibrate_offsets(
    gray: np.ndarray, items: dict, choices: list[str], dpi: float, r_mm: float
) -> tuple[float, float]:
    r_px = max(3, mm_to_px(r_mm, dpi))
    dxs, dys = [], []
    for item_data in items.values():
        if not isinstance(item_data, dict):
            continue
        for ch in choices:
            coord = item_data.get(ch)
            if not isinstance(coord, dict):
                continue
            cx = mm_to_px(float(coord.get("cx_mm", 0)), dpi)
            cy = mm_to_px(float(coord.get("cy_spec_mm", 0)), dpi)
            nx, ny, score = snap_bubble(gray, cx, cy, r_px, dpi)
            if score >= MATCH_TEMPLATE_MIN:
                dxs.append(nx - cx)
                dys.append(ny - cy)
    if len(dxs) < max(4, len(items) // 4):
        return 0.0, 0.0
    return float(np.median(dxs)), float(np.median(dys))


def read_answers(
    binary: np.ndarray,
    gray: np.ndarray,
    layout: dict,
    dpi: float,
    num_choices: int,
) -> list[BubbleReading]:
    items = layout.get("items") or {}
    if not items:
        return []
    grid = layout.get("answer_grid") or {}
    r_mm = float(grid.get("bubble_r_mm") or 2.0)
    r_px = max(3, mm_to_px(r_mm, dpi))
    choices = [chr(65 + i) for i in range(num_choices)]
    med_dx, med_dy = _calibrate_offsets(gray, items, choices, dpi, r_mm)

    readings: list[BubbleReading] = []
    for key in sorted(items.keys(), key=lambda x: int(x) if str(x).isdigit() else 0):
        item_num = int(key) if str(key).isdigit() else 0
        if item_num <= 0:
            continue
        item_data = items[key]
        fills: dict[str, float] = {}
        for ch in choices:
            coord = item_data.get(ch) if isinstance(item_data, dict) else None
            if not isinstance(coord, dict):
                continue
            cx = mm_to_px(float(coord.get("cx_mm", 0)), dpi) + int(round(med_dx))
            cy = mm_to_px(float(coord.get("cy_spec_mm", 0)), dpi) + int(round(med_dy))
            nx, ny, score = snap_bubble(gray, cx, cy, r_px, dpi)
            if score < MATCH_TEMPLATE_MIN:
                nx, ny = cx, cy
            fills[ch] = inner_fill(binary, nx, ny, r_px)
        ans, amb, note = classify_fills(fills)
        ranked = sorted(fills.values(), reverse=True)
        best = ranked[0] if ranked else 0.0
        second = ranked[1] if len(ranked) > 1 else 0.0
        readings.append(
            BubbleReading(
                item_number=item_num,
                detected_answer=ans,
                fill_ratio=best,
                second_fill_ratio=second,
                is_ambiguous=amb,
                is_confirmed=not amb and ans != "?",
                confidence_note=note,
            )
        )
    return readings


def read_id(binary: np.ndarray, gray: np.ndarray, layout: dict, dpi: float) -> Optional[str]:
    idc = layout.get("id_columns")
    if not idc:
        return None
    x0 = float(idc["x0_mm"])
    y_top = float(idc["y_top_spec_mm"])
    cols = int(idc.get("num_cols", 8))
    col_pitch = float(idc["col_pitch_mm"])
    row_pitch = float(idc["row_pitch_mm"])
    r_mm = float(idc.get("bubble_r_mm", 1.75))
    r_px = max(2, mm_to_px(r_mm, dpi))
    chars: list[str] = []
    for c in range(cols):
        fills: dict[str, float] = {}
        cx = mm_to_px(x0 + c * col_pitch, dpi)
        for ri, label in enumerate(ID_LABELS):
            cy = mm_to_px(y_top + ID_FIRST_ROW_OFFSET_MM + ri * row_pitch, dpi)
            fills[label] = inner_fill(binary, cx, cy, r_px)
        ans, amb, _ = classify_fills(fills)
        if amb or ans == "?":
            chars.append("?")
        else:
            chars.append(ans)
    if all(ch == "?" for ch in chars):
        return None
    return "".join(chars)


def detect_assessment_qr(color: Optional[np.ndarray], gray: np.ndarray) -> Optional[str]:
    detector = cv2.QRCodeDetector()
    sources = []
    if color is not None:
        sources.append(color)
    sources.append(gray)
    for src in sources:
        try:
            data, _, _ = detector.detectAndDecode(src)
            if data:
                return data.split("|")[0].strip() or None
        except Exception:
            continue
    return None


def grade(responses: dict, answer_key: dict) -> tuple[int, int, float]:
    if not answer_key:
        return 0, 0, 0.0
    key = {str(k): str(v) for k, v in answer_key.items()}
    correct = sum(1 for k, v in key.items() if responses.get(k) == v)
    n = len(key)
    return correct, n, (correct / n * 100.0) if n else 0.0


def align_sheet(
    gray: np.ndarray, color: Optional[np.ndarray], layout: dict
) -> tuple[np.ndarray, np.ndarray, float, str, bool]:
    """Returns (warped_gray, warped_color, dpi, method, low_confidence)."""
    dpi = float(layout.get("dpi") or TARGET_DPI)
    if dpi < 200:
        dpi = TARGET_DPI
    out_w, out_h = _page_size_px(layout, dpi)
    color_src = color if color is not None else cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)

    centers = detect_aruco_centers(gray)
    dst_map = _fiducial_centers_px(layout, dpi)
    if len(centers) == 4 and len(dst_map) >= 4:
        src_pts = []
        dst_pts = []
        for aid, corner in ARUCO_ID_TO_CORNER.items():
            src_pts.append(centers[aid])
            dst_pts.append(dst_map[corner])
        src = np.array(src_pts, dtype=np.float32)
        dst = np.array(dst_pts, dtype=np.float32)
        H, _ = cv2.findHomography(src, dst, cv2.RANSAC, 3.0)
        if H is not None:
            warped_g = cv2.warpPerspective(gray, H, (out_w, out_h))
            warped_c = cv2.warpPerspective(color_src, H, (out_w, out_h))
            return warped_g, warped_c, dpi, "aruco", False

    quad = detect_page_quad(gray)
    if quad is not None:
        src_q = np.array([quad[0], quad[1], quad[2], quad[3]], dtype=np.float32)
        warped_g = warp_to_page(gray, src_q, out_w, out_h)
        warped_c = warp_to_page(color_src, src_q, out_w, out_h)
        return warped_g, warped_c, dpi, "page_contour", False

    return gray, color_src, dpi, "direct", True


def process_sheet(
    image_path: str,
    layout: dict[str, Any],
    answer_key: Optional[dict] = None,
) -> OmrCoreResult:
    if not _CV:
        raise RuntimeError("opencv-python-headless and numpy are required")

    color = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if color is None:
        return OmrCoreResult(
            student_identifier=None,
            responses={},
            readings=[],
            is_flagged=True,
            flag_reason=f"Could not read image at {image_path}",
            alignment="direct",
            low_confidence=True,
        )
    gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
    assessment_id = detect_assessment_qr(color, gray)

    warped_g, warped_c, dpi, method, low = align_sheet(gray, color, layout)
    flat = flatten_illumination(warped_g)
    binary = adaptive_binary_inv(flat)

    grid = layout.get("answer_grid") or {}
    num_choices = int(grid.get("num_choices") or layout.get("num_choices") or 4)
    items = layout.get("items") or {}
    total_items = int(layout.get("total_items") or len(items) or 0)

    student_id = read_id(binary, flat, layout, dpi)
    readings = read_answers(binary, flat, layout, dpi, num_choices)
    if not readings and total_items:
        readings = [
            BubbleReading(
                item_number=i,
                detected_answer="?",
                fill_ratio=0.0,
                is_ambiguous=True,
                confidence_note="Template missing bubble layout — regenerate PDF",
            )
            for i in range(1, total_items + 1)
        ]

    responses = {
        str(r.item_number): r.detected_answer
        for r in readings
        if r.detected_answer != "?"
    }
    correct, max_score, pct = grade(responses, answer_key or {})
    flagged = [r.item_number for r in readings if r.is_ambiguous]
    reasons = []
    if method == "direct" or low:
        reasons.append(f"Low-confidence alignment ({method})")
    if not items:
        reasons.append("Template missing bubble layout — regenerate PDF")
    if student_id is None or "?" in (student_id or ""):
        reasons.append("Student ID incomplete")
    if flagged:
        reasons.append(f"{len(flagged)} ambiguous item(s)")
    flag_reason = "; ".join(reasons) if reasons else None
    if flag_reason and len(flag_reason) > 255:
        flag_reason = flag_reason[:254] + "…"

    return OmrCoreResult(
        student_identifier=student_id,
        responses=responses,
        readings=readings,
        correct_count=correct,
        max_score=max_score,
        score_percent=pct,
        is_flagged=bool(reasons),
        flag_reason=flag_reason,
        flagged_items=flagged,
        assessment_id=assessment_id,
        alignment=method,
        low_confidence=low,
    )
