"""
Batch OMR Scanner - Process a folder of images against a layout template.
Usage: python batch_scan.py <input_dir> <layout.json> [--output <dir>] [--marker <marker.png>]
"""
import argparse, json, os, sys
from pathlib import Path
from omr_processor import process_omr, load_image

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Batch OMR Scanner")
    parser.add_argument("input_dir", help="Directory containing image files")
    parser.add_argument("layout", help="Path to layout JSON")
    parser.add_argument("--marker", help="Path to corner marker image", default=None)
    parser.add_argument("--output", help="Output directory for results", default="batch_results")
    args = parser.parse_args()

    with open(args.layout) as f:
        layout = json.load(f)
    answer_key = layout.get("answer_key", {})

    os.makedirs(args.output, exist_ok=True)

    extensions = {".png", ".jpg", ".jpeg", ".bmp", ".tiff"}
    image_files = sorted(
        f for f in Path(args.input_dir).iterdir()
        if f.suffix.lower() in extensions
    )

    if not image_files:
        print("No image files found.")
        sys.exit(1)

    results = []
    for img_path in image_files:
        try:
            result = process_omr(str(img_path), layout, answer_key, args.marker)
            results.append({
                "file": img_path.name,
                "student_id": result.student_identifier,
                "score": f"{result.correct_count}/{result.max_score}",
                "percent": result.score_percent,
                "flagged": result.is_flagged,
                "flag_reason": result.flag_reason,
            })
            print(f"  {img_path.name}: {result.correct_count}/{result.max_score} ({result.score_percent:.1f}%)")
        except Exception as e:
            print(f"  {img_path.name}: ERROR - {e}")
            results.append({"file": img_path.name, "error": str(e)})

    # Save batch summary
    summary_path = os.path.join(args.output, "batch_summary.json")
    with open(summary_path, "w") as f:
        json.dump(results, f, indent=2)

    success = sum(1 for r in results if "error" not in r)
    print(f"\nDone: {success}/{len(results)} processed. Summary: {summary_path}")
