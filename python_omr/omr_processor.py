"""
OMR Processor — ShreenidhiBodas/OMR pipeline for ATLAS bubble sheets.

test_grader.py flow:
  1. Resize + grayscale + GaussianBlur + Canny → page contour
  2. four_point_transform → bird's-eye view
  3. Otsu BINARY_INV
  4. findContours → filter bubbles (aspect 0.9–1.1, min 20×20)
  5. sort top-to-bottom → rows → countNonZero → pick highest fill
  6. Column 1: assessment QR + student ID; columns 2–3: answers via layout_metadata
  7. Grade against answer key
"""
import argparse, json, math, os, sys
from dataclasses import dataclass, field
from typing import Optional, Tuple, List
import cv2
import numpy as np

SAMPLE_THRESHOLD = 100
MIN_GAP = 0.10
MIN_JUMP = 0.25
MARGIN_FILL = 0.08
GOOD_FILL = 0.42
HYSTERESIS_MARGIN = 0.06
GAMMA = 0.7
TRUNC_THRESHOLD = 150
MASK_WEIGHT = 0.60
FEATURE_WEIGHT = 0.40
ID_FIRST_ROW_OFFSET_MM = 2.5  # PDF draws first ID row at y_top + 2.5mm


@dataclass
class BubbleReading:
    item_number: int
    detected_answer: str
    fill_ratio: float
    second_fill_ratio: float = 0.0
    is_ambiguous: bool = False
    is_confirmed: bool = False
    confidence_note: str = ""

    def to_dict(self):
        return self.__dict__


@dataclass
class OmrResult:
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

    def to_dict(self):
        return {
            k: ([r.to_dict() for r in v] if k == "readings" else v)
            for k, v in self.__dict__.items()
        }


def load_image(path: str) -> np.ndarray:
    img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(f"Cannot load: {path}")
    return img


def load_color(path: str) -> Optional[np.ndarray]:
    return cv2.imread(path, cv2.IMREAD_COLOR)


def adjust_gamma(img: np.ndarray, gamma: float) -> np.ndarray:
    table = np.array([(i / 255.0) ** (1.0 / gamma) * 255 for i in range(256)]).astype(np.uint8)
    return cv2.LUT(img, table)


def preprocess(img: np.ndarray, gamma: float = GAMMA, trunc: int = TRUNC_THRESHOLD) -> np.ndarray:
    img = cv2.GaussianBlur(img, (3, 3), 0)
    img = cv2.normalize(img, None, 0, 255, cv2.NORM_MINMAX)
    _, img = cv2.threshold(img, trunc, 255, cv2.THRESH_TRUNC)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    img = clahe.apply(img)
    img = adjust_gamma(img, gamma)
    return cv2.normalize(img, None, 0, 255, cv2.NORM_MINMAX)


def order_points(pts: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype=np.float32)
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def four_point_transform(img: np.ndarray, pts: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """Warp page corners to a full page canvas (TL, TR, BR, BL)."""
    rect = order_points(pts.astype(np.float32))
    dst = np.array(
        [[0, 0], [out_w - 1, 0], [out_w - 1, out_h - 1], [0, out_h - 1]],
        dtype=np.float32,
    )
    M = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(img, M, (out_w, out_h))


def detect_page(img: np.ndarray) -> Optional[np.ndarray]:
    """Canny contour page detection — test_grader.py (75, 200), no morph close."""
    h, w = img.shape[:2]
    blurred = cv2.GaussianBlur(img, (5, 5), 0)
    edged = cv2.Canny(blurred, 75, 200)
    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    contours = sorted(contours, key=cv2.contourArea, reverse=True)
    for cnt in contours:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        if len(approx) != 4:
            continue
        pts = approx.reshape(4, 2).astype(np.float32)
        area = cv2.contourArea(pts)
        if not (0.10 <= area / (w * h) <= 0.98):
            continue
        return order_points(pts)
    return None


def find_bubble_contours(thresh: np.ndarray, min_size: int = 20) -> List[np.ndarray]:
    """Reference: boundingRect filter aspect 0.9–1.1, min 20×20."""
    cnts, _ = cv2.findContours(thresh.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    bubbles = []
    h, w = thresh.shape[:2]
    for c in cnts:
        x, y, bw, bh = cv2.boundingRect(c)
        if bw < min_size or bh < min_size:
            continue
        aspect = bw / float(bh)
        if not (0.9 <= aspect <= 1.1):
            continue
        if bw > w * 0.12 or bh > h * 0.06:
            continue
        bubbles.append(c)
    return bubbles


def contour_fill_count(thresh: np.ndarray, contour: np.ndarray) -> int:
    mask = np.zeros(thresh.shape, dtype=np.uint8)
    cv2.drawContours(mask, [contour], -1, 255, -1)
    masked = cv2.bitwise_and(thresh, thresh, mask=mask)
    return int(cv2.countNonZero(masked))


def sort_top_to_bottom(contours: List[np.ndarray]) -> List[np.ndarray]:
    return sorted(contours, key=lambda c: (cv2.boundingRect(c)[1], cv2.boundingRect(c)[0]))


def sort_left_to_right(contours: List[np.ndarray]) -> List[np.ndarray]:
    return sorted(contours, key=lambda c: cv2.boundingRect(c)[0])


def group_into_rows(sorted_contours: List[np.ndarray], row_pitch_px: float) -> List[List[np.ndarray]]:
    if not sorted_contours:
        return []
    rows: List[List[np.ndarray]] = []
    current = [sorted_contours[0]]
    row_y = cv2.boundingRect(sorted_contours[0])[1]
    for c in sorted_contours[1:]:
        y = cv2.boundingRect(c)[1]
        if abs(y - row_y) > row_pitch_px * 0.55:
            rows.append(sort_left_to_right(current))
            current = [c]
            row_y = y
        else:
            current.append(c)
            row_y = int((row_y + y) / 2)
    if current:
        rows.append(sort_left_to_right(current))
    return rows


def read_row(row: List[np.ndarray], thresh: np.ndarray, choices: List[str]) -> Tuple[str, int, int, bool]:
    if not row:
        return "?", 0, 0, True
    fills = [(contour_fill_count(thresh, c), j, c) for j, c in enumerate(row[: len(choices)])]
    if not fills:
        return "?", 0, 0, True
    fills.sort(key=lambda x: x[0], reverse=True)
    best_fill, best_idx, _ = fills[0]
    second_fill = fills[1][0] if len(fills) > 1 else 0
    if best_fill <= 0:
        return "?", 0, second_fill, True
    ambiguous = second_fill > 0 and (best_fill - second_fill) < best_fill * 0.15
    ans = "?" if ambiguous else choices[best_idx] if best_idx < len(choices) else "?"
    return ans, best_fill, second_fill, ambiguous or len(row) < len(choices)


def _left_zone_px(layout: dict, dpi: float):
    lz = layout.get("left_zone")
    if lz:
        grid = layout.get("answer_grid", {})
        col_a = grid.get("col_a", {})
        y_bot = float(col_a.get("y_bottom_spec_mm", 280))
        return (
            mm_to_px(float(lz["x0_mm"]), dpi),
            mm_to_px(float(lz.get("y_start_spec_mm", 80)), dpi),
            mm_to_px(float(lz["x1_mm"]), dpi),
            mm_to_px(y_bot, dpi),
        )
    return mm_to_px(23.0, dpi), mm_to_px(80, dpi), mm_to_px(81.0, dpi), mm_to_px(280, dpi)


def _answer_zone_px(layout: dict, dpi: float):
    grid = layout.get("answer_grid", {})
    y_start = float(grid.get("y_start_spec_mm", 80.0))
    y_end = y_start + 200.0
    for key in ("col_a", "col_b"):
        col = grid.get(key)
        if col and col.get("y_bottom_spec_mm"):
            y_end = max(y_end, float(col["y_bottom_spec_mm"]))
    left_mm = float(grid.get("answer_zone_x0_mm") or grid.get("col_a", {}).get("x0_mm", 83.0))
    right_mm = float(grid.get("answer_zone_x1_mm", 193.0))
    return (
        mm_to_px(left_mm, dpi),
        mm_to_px(y_start, dpi),
        mm_to_px(right_mm, dpi),
        mm_to_px(y_end, dpi),
    )


def _answer_column_zone_px(col_meta: dict, grid: dict, dpi: float, answer_zone):
    x0 = float(col_meta["x0_mm"])
    col_w = float(grid.get("col_width_mm") or (
        float(grid.get("col_b", {}).get("x0_mm", x0)) - x0 - float(grid.get("col_gap_mm", 1.5))
    ))
    left, top, _, bottom = answer_zone
    return mm_to_px(x0, dpi), top, mm_to_px(x0 + col_w, dpi), bottom


def read_answer_bubbles_reference(
    thresh: np.ndarray, layout: dict, dpi: float, total_items: int, num_choices: int
) -> List[BubbleReading]:
    choices = [chr(65 + i) for i in range(num_choices)]
    grid = layout.get("answer_grid", {})
    row_pitch_px = mm_to_px(float(grid.get("row_pitch_mm", 6.0)), dpi)
    all_b = find_bubble_contours(thresh, min_size=20)

    def centroid(c):
        m = cv2.moments(c)
        if m["m00"] == 0:
            x, y, w, h = cv2.boundingRect(c)
            return x + w / 2, y + h / 2
        return m["m10"] / m["m00"], m["m01"] / m["m00"]

    answer_zone = _answer_zone_px(layout, dpi)
    left_px, top_px, right_px, bot_px = answer_zone

    in_zone = [
        c
        for c in all_b
        if left_px <= centroid(c)[0] <= right_px
        and top_px <= centroid(c)[1] <= bot_px
    ]
    results: List[BubbleReading] = []

    def read_col(bubbles, col_meta):
        start = int(col_meta.get("start_item", 1))
        sorted_b = sort_top_to_bottom(bubbles)
        for ri, row in enumerate(group_into_rows(sorted_b, row_pitch_px)):
            ans, bf, sf, amb = read_row(row, thresh, choices)
            results.append(
                BubbleReading(
                    item_number=start + ri,
                    detected_answer=ans,
                    fill_ratio=min(1.0, bf / 500.0),
                    second_fill_ratio=min(1.0, sf / 500.0) if sf else 0.0,
                    is_ambiguous=amb,
                    is_confirmed=not amb and ans != "?",
                    confidence_note=f"Contour fill {bf}",
                )
            )

    col_a_meta, col_b_meta = grid.get("col_a"), grid.get("col_b")
    if col_a_meta:
        zone_a = _answer_column_zone_px(col_a_meta, grid, dpi, answer_zone)
        read_col([c for c in in_zone if zone_a[0] <= centroid(c)[0] <= zone_a[2]], col_a_meta)
    if col_b_meta:
        zone_b = _answer_column_zone_px(col_b_meta, grid, dpi, answer_zone)
        read_col([c for c in in_zone if zone_b[0] <= centroid(c)[0] <= zone_b[2]], col_b_meta)
    elif not col_a_meta:
        sorted_b = sort_top_to_bottom(in_zone)
        for ri, row in enumerate(group_into_rows(sorted_b, row_pitch_px)):
            if ri >= total_items:
                break
            ans, bf, sf, amb = read_row(row, thresh, choices)
            results.append(
                BubbleReading(
                    item_number=ri + 1,
                    detected_answer=ans,
                    fill_ratio=min(1.0, bf / 500.0),
                    second_fill_ratio=min(1.0, sf / 500.0) if sf else 0.0,
                    is_ambiguous=amb,
                    is_confirmed=not amb and ans != "?",
                )
            )

    by_item = {r.item_number: r for r in results}
    out = []
    for i in range(1, total_items + 1):
        out.append(
            by_item.get(i)
            or BubbleReading(
                item_number=i, detected_answer="?", fill_ratio=0.0, is_ambiguous=True, confidence_note="Row not detected"
            )
        )
    return out


def read_id_bubbles_reference(thresh: np.ndarray, layout: dict, dpi: float) -> Optional[str]:
    idc = layout.get("id_columns")
    if not idc:
        return None
    labels = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]
    x0 = float(idc["x0_mm"])
    y_top = float(idc["y_top_spec_mm"])
    cols = int(idc.get("num_cols", 8))
    col_pitch = float(idc["col_pitch_mm"])
    row_pitch = float(idc["row_pitch_mm"])
    left_zone = _left_zone_px(layout, dpi)
    x0px = mm_to_px(x0, dpi)
    y0px = mm_to_px(y_top + ID_FIRST_ROW_OFFSET_MM, dpi)
    x1px = mm_to_px(x0 + cols * col_pitch, dpi)
    y1px = mm_to_px(y_top + ID_FIRST_ROW_OFFSET_MM + len(labels) * row_pitch, dpi)
    col_pitch_px = mm_to_px(col_pitch, dpi)
    row_pitch_px = mm_to_px(row_pitch, dpi)

    def centroid(c):
        m = cv2.moments(c)
        if m["m00"] == 0:
            x, y, w, h = cv2.boundingRect(c)
            return x + w / 2, y + h / 2
        return m["m10"] / m["m00"], m["m01"] / m["m00"]

    id_b = [
        c
        for c in find_bubble_contours(thresh, min_size=10)
        if left_zone[0] <= centroid(c)[0] <= left_zone[2]
        and x0px - col_pitch_px * 0.4 <= centroid(c)[0] <= x1px + col_pitch_px * 0.4
        and y0px - row_pitch_px * 0.4 <= centroid(c)[1] <= y1px + row_pitch_px * 0.4
    ]
    if not id_b:
        return None

    sorted_x = sort_left_to_right(id_b)
    columns: List[List[np.ndarray]] = []
    col: List[np.ndarray] = []
    col_cx = None
    for c in sorted_x:
        cx, _ = centroid(c)
        if col_cx is None or abs(cx - col_cx) <= col_pitch_px * 0.45:
            col.append(c)
            col_cx = cx if col_cx is None else (col_cx + cx) / 2
        else:
            columns.append(col)
            col = [c]
            col_cx = cx
    if col:
        columns.append(col)

    buf = []
    for column in columns:
        rows = group_into_rows(sort_top_to_bottom(column), row_pitch_px)
        if not rows or not rows[0]:
            buf.append("?")
            continue
        ans, _, _, _ = read_row(rows[0], thresh, labels)
        buf.append(ans)
    return "".join(buf) if buf else None


def detect_assessment_qr(color_img: Optional[np.ndarray], gray: np.ndarray) -> Optional[str]:
    """Decode assessment QR from the capture (OpenCV QRCodeDetector)."""
    detector = cv2.QRCodeDetector()
    sources = []
    if color_img is not None:
        sources.append(color_img)
    sources.append(gray)
    for src in sources:
        try:
            data, _, _ = detector.detectAndDecode(src)
            if data:
                return data.split("|")[0].strip() or None
        except Exception:
            continue
    return None


def otsu_binarize_inv(img: np.ndarray) -> np.ndarray:
    blurred = cv2.GaussianBlur(img, (5, 5), 0)
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)
    return thresh


def mask_fill_ratio(binary: np.ndarray, cx: int, cy: int, r: int) -> float:
    if r < 1:
        return 0.0
    h, w = binary.shape[:2]
    yy, xx = np.ogrid[:h, :w]
    mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2
    pixels = binary[mask]
    if len(pixels) == 0:
        return 0.0
    return float(np.sum(pixels > 128) / len(pixels))


def refine_bubble_center(binary: np.ndarray, cx: int, cy: int, r: int, search: int = 6) -> Tuple[int, int]:
    probe = max(2, int(r * 0.7))
    best = mask_fill_ratio(binary, cx, cy, probe)
    # Do not drift empty bubbles onto the printed ring
    if best < 0.12:
        return (cx, cy)
    best_xy = (cx, cy)
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            if dx == 0 and dy == 0:
                continue
            score = mask_fill_ratio(binary, cx + dx, cy + dy, probe)
            if score > best + 0.05:
                best = score
                best_xy = (cx + dx, cy + dy)
    return best_xy


def sample_circle(img: np.ndarray, cx: int, cy: int, r: int) -> float:
    if r < 1:
        return 0.0
    h, w = img.shape
    yy, xx = np.ogrid[:h, :w]
    mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2
    pixels = img[mask]
    if len(pixels) == 0:
        return 0.0
    return float(np.sum(pixels < SAMPLE_THRESHOLD) / len(pixels))


def largest_gap_threshold(fills: list, fallback: float):
    if len(fills) < 2:
        return fallback, 0.0
    sf = sorted(fills)
    max_gap, thr = 0.0, fallback
    for i in range(1, len(sf)):
        gap = sf[i] - sf[i - 1]
        if gap > max_gap:
            max_gap = gap
            thr = sf[i - 1] + gap / 2
    return (thr, max_gap) if max_gap >= MIN_GAP else (fallback, max_gap)


def mm_to_px(mm: float, dpi: float) -> int:
    return int(round(mm * dpi / 25.4))


def read_answer_bubbles(
    binary: np.ndarray,
    gray: np.ndarray,
    items: dict,
    choices: list,
    dpi: float,
    bubble_r_mm: float = 2.0,
) -> list:
    r = max(2, int(round(mm_to_px(bubble_r_mm, dpi) * 0.85)))
    all_fills, raw_items = [], []

    for item_key in sorted(items.keys(), key=lambda x: int(x)):
        item_data = items[item_key]
        item_num = int(item_key)
        per_mask, per_feat = [], []
        best_h, second_h = -1.0, -1.0
        best_choice, best_mask, second_mask = "?", 0.0, 0.0

        for ch in choices:
            coord = item_data.get(ch)
            if coord is None:
                per_mask.append(0.0)
                per_feat.append(0.0)
                continue
            cx = mm_to_px(float(coord.get("cx_mm", 0)), dpi)
            cy = mm_to_px(float(coord.get("cy_spec_mm", 0)), dpi)
            cx, cy = refine_bubble_center(binary, cx, cy, r)
            mask = mask_fill_ratio(binary, cx, cy, r)
            feat = sample_circle(gray, cx, cy, r)
            hybrid = MASK_WEIGHT * mask + FEATURE_WEIGHT * feat
            per_mask.append(mask)
            per_feat.append(feat)
            if hybrid > best_h:
                second_h, second_mask = best_h, best_mask
                best_h, best_mask, best_choice = hybrid, mask, ch
            elif hybrid > second_h:
                second_h, second_mask = hybrid, mask

        raw_items.append(
            dict(
                item_number=item_num,
                fills=per_mask,
                hybrids=[MASK_WEIGHT * m + FEATURE_WEIGHT * f for m, f in zip(per_mask, per_feat)],
                best_choice=best_choice,
                best_fill=best_mask,
                best_hybrid=max(best_h, 0.0),
                second_fill=second_mask,
                second_hybrid=max(second_h, 0.0),
            )
        )
        all_fills.extend(per_mask)

    global_thr, _ = largest_gap_threshold(all_fills, 0.40)
    # Also consider hybrids for threshold
    all_hybrids = [h for raw in raw_items for h in raw["hybrids"]]
    hybrid_thr, _ = largest_gap_threshold(all_hybrids, global_thr)
    score_thr = max(global_thr, hybrid_thr)

    results = []
    for raw in raw_items:
        fills = raw["hybrids"]
        if not fills:
            results.append(
                BubbleReading(
                    item_number=raw["item_number"],
                    detected_answer="?",
                    fill_ratio=0.0,
                    is_ambiguous=True,
                    confidence_note="No layout data",
                )
            )
            continue
        stddev = float(np.std(fills)) if len(fills) >= 2 else 0.0
        no_outliers = stddev < 0.05
        local_thr, max_gap = largest_gap_threshold(fills, score_thr)
        if max_gap < MIN_GAP:
            eff_thr, low_conf, src = score_thr, True, "global"
        elif max_gap < MIN_JUMP and not no_outliers:
            eff_thr, low_conf, src = max(local_thr, score_thr - HYSTERESIS_MARGIN), True, "hysteresis"
        elif no_outliers:
            eff_thr, low_conf, src = score_thr, True, "global"
        else:
            eff_thr, low_conf, src = max(local_thr, score_thr - HYSTERESIS_MARGIN), False, "local"

        passes = raw["best_hybrid"] >= eff_thr and raw["best_hybrid"] >= (score_thr - HYSTERESIS_MARGIN)
        is_amb = (
            not passes
            or abs(raw["best_hybrid"] - raw["second_hybrid"]) < MARGIN_FILL
            or low_conf
        )
        is_conf = not is_amb and raw["best_fill"] >= GOOD_FILL
        if is_amb:
            note = (
                f"No outliers (~{raw['best_hybrid']:.2f})"
                if no_outliers
                else f"Low fill ({raw['best_fill']:.2f} hybrid {raw['best_hybrid']:.2f} vs {eff_thr:.2f})"
                if raw["best_hybrid"] < eff_thr
                else f"Below global ({score_thr - HYSTERESIS_MARGIN:.2f})"
                if not passes
                else f"Low conf ({src}, gap {max_gap:.2f})"
                if low_conf
                else f"Too close ({raw['best_hybrid']:.2f} vs {raw['second_hybrid']:.2f})"
            )
        else:
            note = f"{'Confirmed' if is_conf else 'Acceptable'} (mask={raw['best_fill']:.2f}, {src})"
        results.append(
            BubbleReading(
                item_number=raw["item_number"],
                detected_answer="?" if is_amb else raw["best_choice"],
                fill_ratio=raw["best_fill"],
                second_fill_ratio=raw["second_fill"],
                is_ambiguous=is_amb,
                is_confirmed=is_conf,
                confidence_note=note,
            )
        )
    return results


def read_id_bubbles(binary: np.ndarray, layout: dict, dpi: float) -> Optional[str]:
    idc = layout.get("id_columns")
    if idc is None:
        return None
    x0_mm = idc["x0_mm"]
    y_top_mm = idc["y_top_spec_mm"]
    cols = idc.get("num_cols", 8)
    col_pitch = idc["col_pitch_mm"]
    row_pitch = idc["row_pitch_mm"]
    r_mm = idc.get("bubble_r_mm", 1.5)
    r_px = mm_to_px(r_mm, dpi)
    labels = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]
    all_col_fills = []
    for c in range(cols):
        cx = mm_to_px(x0_mm + c * col_pitch, dpi)
        fills = []
        for r in range(len(labels)):
            cy = mm_to_px(y_top_mm + ID_FIRST_ROW_OFFSET_MM + r * row_pitch, dpi)
            rcx, rcy = refine_bubble_center(binary, cx, cy, r_px)
            fills.append(mask_fill_ratio(binary, rcx, rcy, r_px))
        all_col_fills.append(fills)
    all_f = [f for cf in all_col_fills for f in cf]
    global_thr, _ = largest_gap_threshold(all_f, 0.40)
    buf = []
    for fills in all_col_fills:
        local_thr, _ = largest_gap_threshold(fills, global_thr)
        best_fill, best_row = 0.0, -1
        for r, f in enumerate(fills):
            if f > best_fill:
                best_fill, best_row = f, r
        buf.append(labels[best_row] if best_row != -1 and best_fill >= local_thr else "?")
    return "".join(buf)


def grade(responses: dict, answer_key: dict):
    if not answer_key:
        return 0, 0, 0.0
    correct = sum(1 for k, v in answer_key.items() if responses.get(k) == v)
    return correct, len(answer_key), (correct / len(answer_key) * 100.0) if answer_key else 0.0


def process_omr(
    image_path: str,
    layout: dict,
    answer_key: dict = None,
    marker_path: str = None,
) -> OmrResult:
    gray = load_image(image_path)
    color = load_color(image_path)

    assessment_id = detect_assessment_qr(color, gray)

    page_w_pt = float(layout.get("page_width_pt", 612.0))
    page_h_pt = float(layout.get("page_height_pt", 936.0))
    target_dpi = float(layout.get("dpi", 150))
    out_w = max(200, int(round((page_w_pt / 72.0) * target_dpi)))
    out_h = max(200, int(round((page_h_pt / 72.0) * target_dpi)))

    # Reference: optional resize to width 700 before page detect
    work = gray
    scale_back = 1.0
    if work.shape[1] > 700:
        scale_back = work.shape[1] / 700.0
        work = cv2.resize(work, (700, int(work.shape[0] / scale_back)))

    page_pts = detect_page(work)
    alignment_ok = page_pts is not None
    if alignment_ok and scale_back != 1.0:
        page_pts = (page_pts * scale_back).astype(np.float32)
        work = gray

    if alignment_ok:
        warped = four_point_transform(work, page_pts, out_w, out_h)
        dpi = target_dpi
    else:
        warped = work
        dpi = warped.shape[1] / (page_w_pt / 72.0)

    binary = otsu_binarize_inv(warped)
    student_id = read_id_bubbles(binary, layout, dpi)

    grid = layout.get("answer_grid", {})
    num_choices = int(grid.get("num_choices", layout.get("num_choices", 4)))
    items = layout.get("items", {})
    total_items = int(layout.get("total_items", len(items) or 0))
    if not total_items and items:
        total_items = max(int(k) for k in items.keys())

    if items:
        readings = read_answer_bubbles(
            binary, warped, items, [chr(65 + i) for i in range(num_choices)], dpi
        )
        confirmed = sum(1 for r in readings if r.detected_answer != "?" and not r.is_ambiguous)
        if confirmed < max(1, int(total_items * 0.15)):
            contour_readings = read_answer_bubbles_reference(
                binary, layout, dpi, total_items, num_choices
            )
            contour_confirmed = sum(
                1 for r in contour_readings if r.detected_answer != "?" and not r.is_ambiguous
            )
            if contour_confirmed > confirmed:
                readings = contour_readings
    else:
        readings = read_answer_bubbles_reference(binary, layout, dpi, total_items, num_choices)

    responses = {str(r.item_number): r.detected_answer for r in readings if r.detected_answer != "?"}
    correct, max_score, pct = grade(responses, answer_key or {})

    flagged = [r.item_number for r in readings if r.is_ambiguous]
    reasons = []
    if not alignment_ok:
        reasons.append("Page alignment failed")
    if student_id is None or "?" in (student_id or ""):
        reasons.append("Student ID incomplete")
    if flagged:
        reasons.append(f"{len(flagged)} ambiguous item(s)")

    flag_reason = "; ".join(reasons) if reasons else None
    if flag_reason and len(flag_reason) > 255:
        flag_reason = flag_reason[:254] + "…"

    return OmrResult(
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
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="OMR Processor (hybrid)")
    parser.add_argument("image", help="Path to image file")
    parser.add_argument("layout", help="Path to layout JSON")
    parser.add_argument("--marker", help="Path to corner marker image", default=None)
    parser.add_argument("--output", help="Output directory for JSON", default=".")
    args = parser.parse_args()

    with open(args.layout) as f:
        layout = json.load(f)

    answer_key = layout.get("answer_key", {})
    result = process_omr(args.image, layout, answer_key, args.marker)

    out_path = os.path.join(args.output, "omr_result.json")
    with open(out_path, "w") as f:
        json.dump(result.to_dict(), f, indent=2)

    print(f"✓ Processed: {args.image}")
    print(f"  Assessment ID: {result.assessment_id}")
    print(f"  Student ID: {result.student_identifier}")
    print(f"  Score: {result.correct_count}/{result.max_score} ({result.score_percent:.1f}%)")
    print(f"  Flagged: {result.is_flagged}")
    if result.flag_reason:
        print(f"  Reason: {result.flag_reason}")
    print(f"  Output: {out_path}")
