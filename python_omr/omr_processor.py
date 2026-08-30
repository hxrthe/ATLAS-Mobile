"""
OMR Processor — hybrid pipeline for ATLAS bubble sheets.

Inspired by ShreenidhiBodas/OMR + ATLAS layout metadata:
  1. Contour-first page detection (Canny → largest quadrilateral)
  2. four_point_transform onto a full page canvas at fixed DPI
  3. Otsu BINARY_INV on warped grayscale
  4. Mask fill counting at template positions (+ local centre refine)
  5. Hybrid score = 0.60*mask + 0.40*luminance-fill (borderline aid)
  6. Student ID + grade + flag
  7. Optional assessment QR via OpenCV QRCodeDetector
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
    """Canny contour page detection — ShreenidhiBodas/OMR style (75, 200)."""
    h, w = img.shape[:2]
    blurred = cv2.GaussianBlur(img, (5, 5), 0)
    edges = cv2.Canny(blurred, 75, 200)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel)
    contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]
    for cnt in contours:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        if len(approx) != 4:
            continue
        pts = approx.reshape(4, 2).astype(np.float32)
        area = cv2.contourArea(pts)
        if not (0.15 <= area / (w * h) <= 0.95):
            continue
        max_cos = 0.0
        for i in range(4):
            a, b, c = pts[i], pts[(i + 1) % 4], pts[(i + 2) % 4]
            ab, bc = np.linalg.norm(a - b), np.linalg.norm(b - c)
            if ab > 0 and bc > 0:
                max_cos = max(
                    max_cos,
                    abs((ab * ab + bc * bc - np.linalg.norm(c - a) ** 2) / (2 * ab * bc)),
                )
        if max_cos >= 0.35:
            continue
        return order_points(pts)
    return None


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

    page_pts = detect_page(gray)
    alignment_ok = page_pts is not None
    if alignment_ok:
        warped = four_point_transform(gray, page_pts, out_w, out_h)
        dpi = target_dpi
    else:
        warped = gray
        dpi = warped.shape[1] / (page_w_pt / 72.0)

    # Otsu on lightly blurred warp (reference style)
    binary = otsu_binarize_inv(warped)
    gray_enh = preprocess(warped)

    student_id = read_id_bubbles(binary, layout, dpi)

    grid = layout.get("answer_grid", {})
    items = layout.get("items", {})
    num_choices = grid.get("num_choices", layout.get("num_choices", 4))
    if isinstance(num_choices, str):
        num_choices = 4
    # Infer from first item if needed
    if items:
        sample = next(iter(items.values()))
        if isinstance(sample, dict):
            num_choices = max(num_choices, len([k for k in sample if k in "ABCDEFGH"]))
    choices = [chr(65 + i) for i in range(int(num_choices))]
    bubble_r_mm = float(grid.get("bubble_r_mm", 2.0))
    readings = read_answer_bubbles(binary, gray_enh, items, choices, dpi, bubble_r_mm)

    responses = {str(r.item_number): r.detected_answer for r in readings if r.detected_answer != "?"}
    correct, max_score, pct = grade(responses, answer_key or {})

    flagged = [r.item_number for r in readings if r.is_ambiguous]
    reasons = []
    if not alignment_ok:
        reasons.append("Page alignment weak")
    if student_id is None or "?" in student_id:
        reasons.append("Student ID incomplete")
    if flagged:
        reasons.append(f"{len(flagged)} ambiguous item(s)")

    return OmrResult(
        student_identifier=student_id,
        responses=responses,
        readings=readings,
        correct_count=correct,
        max_score=max_score,
        score_percent=pct,
        is_flagged=bool(reasons),
        flag_reason="; ".join(reasons) if reasons else None,
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
