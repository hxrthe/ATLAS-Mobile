"""
OMR Processor - Python OMR pipeline based on OMRChecker + AndroidOMRHelper.
Usage: python omr_processor.py <image> <layout.json> [--marker <marker.png>] [--output <dir>]
"""
import argparse, json, math, os, sys
from dataclasses import dataclass, field
from typing import Optional
import cv2, numpy as np

# ── Constants ──
SAMPLE_THRESHOLD = 100; MIN_GAP = 0.10; MIN_JUMP = 0.25; MARGIN_FILL = 0.08
GOOD_FILL = 0.42; HYSTERESIS_MARGIN = 0.06; GAMMA = 0.7; TRUNC_THRESHOLD = 150

@dataclass
class BubbleReading:
    item_number: int; detected_answer: str; fill_ratio: float
    second_fill_ratio: float = 0.0; is_ambiguous: bool = False
    is_confirmed: bool = False; confidence_note: str = ""
    def to_dict(self): return self.__dict__

@dataclass
class OmrResult:
    student_identifier: Optional[str]; responses: dict; readings: list
    correct_count: int = 0; max_score: int = 0; score_percent: float = 0.0
    is_flagged: bool = False; flag_reason: Optional[str] = None
    flagged_items: list = field(default_factory=list)
    def to_dict(self):
        return {k: ([r.to_dict() for r in v] if k == "readings" else v)
                for k, v in self.__dict__.items()}

# ── Image I/O ──
def load_image(path: str) -> np.ndarray:
    img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if img is None: raise FileNotFoundError(f"Cannot load: {path}")
    return img

# ── Preprocessing ──
def adjust_gamma(img: np.ndarray, gamma: float) -> np.ndarray:
    table = np.array([(i/255.0)**(1.0/gamma)*255 for i in range(256)]).astype(np.uint8)
    return cv2.LUT(img, table)

def preprocess(img: np.ndarray) -> np.ndarray:
    img = cv2.GaussianBlur(img, (3, 3), 0)
    img = cv2.normalize(img, None, 0, 255, cv2.NORM_MINMAX)
    _, img = cv2.threshold(img, TRUNC_THRESHOLD, 255, cv2.THRESH_TRUNC)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    img = clahe.apply(img)
    img = adjust_gamma(img, GAMMA)
    return cv2.normalize(img, None, 0, 255, cv2.NORM_MINMAX)

# ── Page Detection ──
def order_points(pts: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype=np.float32)
    s = pts.sum(axis=1); rect[0] = pts[np.argmin(s)]; rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1); rect[1] = pts[np.argmin(diff)]; rect[3] = pts[np.argmax(diff)]
    return rect

def four_point_transform(img: np.ndarray, pts: np.ndarray) -> np.ndarray:
    rect = order_points(pts)
    (tl, tr, br, bl) = rect
    max_w = max(int(np.linalg.norm(br-bl)), int(np.linalg.norm(tr-tl)))
    max_h = max(int(np.linalg.norm(tr-br)), int(np.linalg.norm(tl-bl)))
    dst = np.array([[0,0],[max_w-1,0],[max_w-1,max_h-1],[0,max_h-1]], dtype=np.float32)
    M = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(img, M, (max_w, max_h))

def detect_page(img: np.ndarray) -> Optional[np.ndarray]:
    h, w = img.shape
    blurred = cv2.GaussianBlur(img, (3,3), 0)
    normed = cv2.normalize(blurred, None, 0, 255, cv2.NORM_MINMAX)
    _, trunc = cv2.threshold(normed, 200, 255, cv2.THRESH_TRUNC)
    normed = cv2.normalize(trunc, None, 0, 255, cv2.NORM_MINMAX)
    edges = cv2.Canny(normed, 55, 185)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5,5))
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel)
    contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours: return None
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]
    for cnt in contours:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.025*peri, True)
        if len(approx) != 4: continue
        pts = approx.reshape(4, 2).astype(np.float32)
        area = cv2.contourArea(pts)
        if not (0.15 <= area/(w*h) <= 0.95): continue
        # Max cosine check
        max_cos = 0.0
        for i in range(4):
            a, b, c = pts[i], pts[(i+1)%4], pts[(i+2)%4]
            ab, bc = np.linalg.norm(a-b), np.linalg.norm(b-c)
            if ab>0 and bc>0:
                max_cos = max(max_cos, abs((ab*ab+bc*bc-np.linalg.norm(c-a)**2)/(2*ab*bc)))
        if max_cos >= 0.35: continue
        return order_points(pts)
    return None

# ── Bubble detection ──
def sample_circle(img: np.ndarray, cx: int, cy: int, r: int) -> float:
    if r < 1: return 0.0
    h, w = img.shape
    yy, xx = np.ogrid[:h, :w]
    mask = (xx-cx)**2 + (yy-cy)**2 <= r**2
    pixels = img[mask]
    if len(pixels) == 0: return 0.0
    return float(np.sum(pixels < SAMPLE_THRESHOLD) / len(pixels))

def largest_gap_threshold(fills: list, fallback: float):
    if len(fills) < 2: return fallback, 0.0
    sf = sorted(fills); max_gap, thr = 0.0, fallback
    for i in range(1, len(sf)):
        gap = sf[i]-sf[i-1]
        if gap > max_gap: max_gap = gap; thr = sf[i-1]+gap/2
    return (thr, max_gap) if max_gap >= MIN_GAP else (fallback, max_gap)

def read_answer_bubbles(img: np.ndarray, items: dict, choices: list, dpi: float) -> list:
    all_fills, raw_items = [], []
    for item_key in sorted(items.keys(), key=lambda x: int(x)):
        item_data = items[item_key]; item_num = int(item_key)
        per_item, best_fill, best_choice, second_fill = [], 0.0, "?", 0.0
        for ch in choices:
            coord = item_data.get(ch)
            if coord is None: per_item.append(0.0); continue
            cx = round(coord.get("cx_mm",0)*dpi/25.4)
            cy = round(coord.get("cy_spec_mm",0)*dpi/25.4)
            r_mm = float(item_data.get("bubble_r_mm", 2.0))
            r = round(r_mm*dpi/25.4)
            fill = sample_circle(img, cx, cy, r); per_item.append(fill)
            if fill > best_fill: second_fill=best_fill; best_fill=fill; best_choice=ch
            elif fill > second_fill: second_fill = fill
        raw_items.append(dict(item_number=item_num, fills=per_item,
            best_choice=best_choice, best_fill=best_fill, second_fill=second_fill))
        all_fills.extend(per_item)

    global_thr, _ = largest_gap_threshold(all_fills, 0.40)
    results = []
    for raw in raw_items:
        fills = raw["fills"]
        if not fills:
            results.append(BubbleReading(item_number=raw["item_number"],
                detected_answer="?", fill_ratio=0.0, is_ambiguous=True,
                confidence_note="No layout data")); continue
        stddev = float(np.std(fills)) if len(fills)>=2 else 0.0
        no_outliers = stddev < 0.05
        local_thr, max_gap = largest_gap_threshold(fills, global_thr)
        if max_gap < MIN_GAP:
            eff_thr, low_conf, src = global_thr, True, "global"
        elif max_gap < MIN_JUMP and not no_outliers:
            eff_thr, low_conf, src = max(local_thr, global_thr-HYSTERESIS_MARGIN), True, "hysteresis"
        elif no_outliers:
            eff_thr, low_conf, src = global_thr, True, "global"
        else:
            eff_thr, low_conf, src = max(local_thr, global_thr-HYSTERESIS_MARGIN), False, "local"
        passes = raw["best_fill"]>=eff_thr and raw["best_fill"]>=(global_thr-HYSTERESIS_MARGIN)
        is_amb = not passes or abs(raw["best_fill"]-raw["second_fill"])<MARGIN_FILL or low_conf
        is_conf = not is_amb and raw["best_fill"]>=GOOD_FILL
        if is_amb:
            note = (f"No outliers (~{raw['best_fill']:.2f})" if no_outliers else
                    f"Low fill ({raw['best_fill']:.2f} vs {eff_thr:.2f})" if raw["best_fill"]<eff_thr else
                    f"Below global ({global_thr-HYSTERESIS_MARGIN:.2f})" if not passes else
                    f"Low conf ({src}, gap {max_gap:.2f})" if low_conf else
                    f"Too close ({raw['best_fill']:.2f} vs {raw['second_fill']:.2f})")
        else:
            note = f"{'Confirmed' if is_conf else 'Acceptable'} ({raw['best_fill']:.2f}, {src})"
        results.append(BubbleReading(item_number=raw["item_number"],
            detected_answer="?" if is_amb else raw["best_choice"],
            fill_ratio=raw["best_fill"], second_fill_ratio=raw["second_fill"],
            is_ambiguous=is_amb, is_confirmed=is_conf, confidence_note=note))
    return results

def read_id_bubbles(img: np.ndarray, layout: dict, dpi: float) -> Optional[str]:
    idc = layout.get("id_columns")
    if idc is None: return None
    x0_mm = idc["x0_mm"]; y_top_mm = idc["y_top_spec_mm"]
    cols = idc.get("num_cols", 8); col_pitch = idc["col_pitch_mm"]
    row_pitch = idc["row_pitch_mm"]; r_mm = idc.get("bubble_r_mm", 1.5)
    r_px = round(r_mm*dpi/25.4)
    labels = ["0","1","2","3","4","5","6","7","8","9","-"]
    all_col_fills = []
    for c in range(cols):
        cx = round((x0_mm+c*col_pitch)*dpi/25.4)
        fills = [sample_circle(img, cx, round((y_top_mm+r*row_pitch)*dpi/25.4), r_px) for r in range(len(labels))]
        all_col_fills.append(fills)
    all_f = [f for cf in all_col_fills for f in cf]
    global_thr, _ = largest_gap_threshold(all_f, 0.40)
    buf = []
    for fills in all_col_fills:
        local_thr, _ = largest_gap_threshold(fills, global_thr)
        best_fill, best_row = 0.0, -1
        for r, f in enumerate(fills):
            if f > best_fill: best_fill = f; best_row = r
        buf.append(labels[best_row] if best_row!=-1 and best_fill>=local_thr else "?")
    return "".join(buf)

# ── Grading ──
def grade(responses: dict, answer_key: dict):
    if not answer_key: return 0, 0, 0.0
    correct = sum(1 for k,v in answer_key.items() if responses.get(k)==v)
    return correct, len(answer_key), (correct/len(answer_key)*100.0) if answer_key else 0.0

# ── Main pipeline ──
def process_omr(image_path: str, layout: dict, answer_key: dict = None,
                marker_path: str = None) -> OmrResult:
    img = load_image(image_path)
    h, w = img.shape

    # Step 1: Page detection
    page_pts = detect_page(img)
    if page_pts is not None:
        img = four_point_transform(img, page_pts)

    # Step 2: Preprocess
    img = preprocess(img)

    # Step 3: DPI estimation
    page_w_pt = layout.get("page_width_pt", 595.28)
    dpi = img.shape[1] / (page_w_pt / 72.0)

    # Step 4: ID bubbles
    student_id = read_id_bubbles(img, layout, dpi)

    # Step 5: Answer bubbles
    grid = layout.get("answer_grid", {})
    items = layout.get("items", {})
    num_choices = grid.get("num_choices", 4)
    choices = [chr(65+i) for i in range(num_choices)]
    readings = read_answer_bubbles(img, items, choices, dpi)

    # Step 6: Build responses and grade
    responses = {str(r.item_number): r.detected_answer for r in readings if r.detected_answer != "?"}
    correct, max_score, pct = grade(responses, answer_key or {})

    # Step 7: Flagging
    flagged = [r.item_number for r in readings if r.is_ambiguous]
    reasons = []
    if student_id is None or "?" in student_id: reasons.append("Student ID incomplete")
    if flagged: reasons.append(f"{len(flagged)} ambiguous item(s)")

    return OmrResult(
        student_identifier=student_id, responses=responses, readings=readings,
        correct_count=correct, max_score=max_score, score_percent=pct,
        is_flagged=bool(reasons), flag_reason="; ".join(reasons) if reasons else None,
        flagged_items=flagged)

# ── CLI ──
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="OMR Processor")
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
    print(f"  Student ID: {result.student_identifier}")
    print(f"  Score: {result.correct_count}/{result.max_score} ({result.score_percent:.1f}%)")
    print(f"  Flagged: {result.is_flagged}")
    if result.flag_reason: print(f"  Reason: {result.flag_reason}")
    print(f"  Output: {out_path}")
