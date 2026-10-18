#!/usr/bin/env python3
"""Compare opt-in RootTabMotionComparisonTests captures (stdlib only).

Usage:
    python3 Scripts/analyze_tab_motion.py /tmp/nako-core-animation-comparison/*.json
    python3 Scripts/analyze_tab_motion.py --format json baseline.json candidate.json

The harness samples presentation layers on display-link callbacks. These are
simulator observations, not render/GPU timings or physical-device measurements.
"""

import argparse
import json
import math
from pathlib import Path
import statistics


ORDER = ("home", "scanner", "profile", "search")
TRAVEL = 30.0
OPACITY_TOLERANCE = 0.001
POSITION_TOLERANCE = 0.03
CAVEATS = [
    "Request latency includes SwiftUI updates, UIKit transition setup and sample scheduling; it is separate from animation duration.",
    "First-observed-motion latency is an upper bound: the first captured frame may already be partway through the animation.",
    "Ease-out fits infer onset and duration from intermediate samples using the standard (0,0,0.58,1) cubic; they are estimates, not instrumentation of animator start/end callbacks.",
    "Endpoint brackets use opacity >= 0.999 and translation <= 0.03pt; relative-to-first-motion intervals omit any unsampled beginning.",
    "Interrupted outgoing snapshots are not sampled by the harness. JSON can verify final selection and live host motion, but not snapshot continuity, flashes, camera pixels or perceived smoothness; inspect recordings.",
    "Display-link intervals measure callback delivery in Simulator, not rendered frames, GPU work, or physical-device performance. Toolbar bounds are layout geometry, not pixel-level presentation motion.",
]


def distribution(values):
    values = sorted(v for v in values if v is not None and math.isfinite(v))
    if not values:
        return None
    index = (len(values) - 1) * 0.95
    lo, hi = math.floor(index), math.ceil(index)
    return {
        "count": len(values), "min": min(values), "median": statistics.median(values),
        "p95": values[lo] + (values[hi] - values[lo]) * (index - lo), "max": max(values),
    }


def ease_out_time_fraction(progress):
    # Invert y(u) = 3u² - 2u³, then evaluate x(u) for (0,0,0.58,1).
    lo, hi = 0.0, 1.0
    for _ in range(40):
        parameter = (lo + hi) / 2
        if 3 * parameter**2 - 2 * parameter**3 < progress:
            lo = parameter
        else:
            hi = parameter
    parameter = (lo + hi) / 2
    return 1.74 * parameter**2 - 0.74 * parameter**3


def fit_ease_out(points, request_time):
    values = [(ease_out_time_fraction(p), t) for t, p in points if 0.01 < p < 0.99]
    if len(values) < 3:
        return None
    mean_x = statistics.mean(x for x, _ in values)
    mean_y = statistics.mean(y for _, y in values)
    denominator = sum((x - mean_x)**2 for x, _ in values)
    if denominator < 1e-9:
        return None
    duration = sum((x - mean_x) * (y - mean_y) for x, y in values) / denominator
    onset = mean_y - duration * mean_x
    residuals = [1000 * (y - onset - duration * x) for x, y in values]
    return {
        "samples": len(values), "duration_ms": 1000 * duration,
        "onset_after_request_ms": 1000 * (onset - request_time),
        "residual_rms_ms": math.sqrt(statistics.mean(r * r for r in residuals)),
        "residual_max_ms": max(abs(r) for r in residuals),
    }


def endpoint_bracket(points, is_endpoint, request_time, first_motion_time):
    previous_time = first_motion_time
    for time, page in points:
        if time < first_motion_time:
            continue
        if is_endpoint(page):
            return {
                "after_request_ms": [1000 * (previous_time - request_time), 1000 * (time - request_time)],
                "after_first_observed_motion_ms": [1000 * (previous_time - first_motion_time), 1000 * (time - first_motion_time)],
            }
        previous_time = time
    return None


def analyze_transition(event, samples, origin, axis):
    target = event["target"]
    sign = 1 if ORDER.index(target) > ORDER.index(origin) else -1
    coordinate = "x" if axis == "horizontal" else "y"
    orthogonal = "y" if axis == "horizontal" else "x"
    points = []
    paired = []
    motions = []
    for sample in samples:
        pages = {p["tab"]: p for p in sample["pages"]}
        incoming, outgoing = pages[target], pages[origin]
        if incoming["attached"]:
            points.append((sample["time"], incoming))
        if incoming["attached"] and outgoing["attached"] and sample.get("activeMotion") and not sample["usesSnapshot"]:
            paired.append((incoming, outgoing))
        if sample.get("activeMotion"):
            motions.append(sample["activeMotion"])
    moving = [(time, p) for time, p in points if abs(p[coordinate]) > POSITION_TOLERANCE or p["opacity"] < 1 - OPACITY_TOLERANCE]
    first = moving[0][0] if moving else None
    expected_motion = [sign * TRAVEL, 0] if axis == "horizontal" else [0, sign * TRAVEL]
    direction_ok = bool(moving) and all(p[coordinate] * sign >= -POSITION_TOLERANCE for _, p in moving)
    direction_ok = direction_ok and all(outgoing[coordinate] * sign <= POSITION_TOLERANCE for _, outgoing in paired)
    motion_ok = bool(motions) and all(all(abs(a - b) < 0.001 for a, b in zip(motion, expected_motion)) for motion in motions)
    fade = fit_ease_out([(t, p["opacity"]) for t, p in points], event["time"])
    slide = fit_ease_out([(t, 1 - p[coordinate] / (sign * TRAVEL)) for t, p in points], event["time"])
    settled = next((s["time"] for s in samples if first is not None and s["time"] >= first and not s.get("activeMotion") and s["selection"] == target), None)
    monotonicity = {
        "opacity_max_reverse": max([0.0] + [a[1]["opacity"] - b[1]["opacity"] for a, b in zip(points, points[1:])]),
        "translation_max_reverse_pt": max([0.0] + [(b[1][coordinate] - a[1][coordinate]) * sign for a, b in zip(points, points[1:])]),
    }
    return {
        "phase": event["phase"], "from": origin, "to": target,
        "direction_matches_order": direction_ok, "active_motion_matches_30pt_axis": motion_ok,
        "first_observed_motion_after_request_ms": None if first is None else 1000 * (first - event["time"]),
        "fade_ease_out_fit": fade, "slide_ease_out_fit": slide,
        "fade_endpoint": None if first is None else endpoint_bracket(points, lambda p: p["opacity"] >= 1 - OPACITY_TOLERANCE, event["time"], first),
        "slide_endpoint": None if first is None else endpoint_bracket(points, lambda p: abs(p[coordinate]) <= POSITION_TOLERANCE, event["time"], first),
        "native_settled_after_request_ms": None if settled is None else 1000 * (settled - event["time"]),
        "paired_30pt_travel_max_error": max([0.0] + [abs((a[coordinate] - b[coordinate]) - sign * TRAVEL) for a, b in paired]),
        "orthogonal_motion_max_pt": max([0.0] + [abs(p[orthogonal]) for _, p in points]),
        "monotonicity": monotonicity,
    }


def analyze_file(path):
    data = json.loads(path.read_text())
    samples, events = data["samples"], data["events"]
    axis = data["axis"]
    if axis not in ("horizontal", "vertical") or not samples:
        raise ValueError(f"{path}: unsupported axis or no samples")
    ordinary = []
    interrupted = []
    previous_target = "home"
    for index, event in enumerate(events):
        end = events[index + 1]["time"] if index + 1 < len(events) else math.inf
        phase_samples = [s for s in samples if event["time"] <= s["time"] < end]
        if ".normal." in event["phase"]:
            ordinary.append(analyze_transition(event, phase_samples, previous_target, axis))
        elif event["phase"] not in ("ready", "finished"):
            interrupted.append({
                "phase": event["phase"], "target": event["target"],
                "actual_until_next_event_ms": None if math.isinf(end) else 1000 * (end - event["time"]),
                "sample_count": len(phase_samples),
                "snapshot_sample_count": sum(s["usesSnapshot"] for s in phase_samples),
                "last_selection": phase_samples[-1]["selection"] if phase_samples else None,
                "active_at_last_sample": bool(phase_samples[-1].get("activeMotion")) if phase_samples else None,
            })
        previous_target = event["target"]
    intervals = [1000 * (b["time"] - a["time"]) for a, b in zip(samples, samples[1:])]
    interval_stats = distribution(intervals)
    toolbar_spans = [max(s["toolbar"][i] for s in samples) - min(s["toolbar"][i] for s in samples) for i in range(4)]
    scale_error = max(abs(p[key] - 1) for s in samples for p in s["pages"] if p["attached"] for key in ("scaleX", "scaleY"))
    summary = {
        "ordinary_transitions": len(ordinary),
        "direction_failures": sum(not t["direction_matches_order"] for t in ordinary),
        "motion_contract_failures": sum(not t["active_motion_matches_30pt_axis"] for t in ordinary),
        "first_observed_motion_after_request_ms": distribution(t["first_observed_motion_after_request_ms"] for t in ordinary),
        "fade_fit_duration_ms": distribution(t["fade_ease_out_fit"]["duration_ms"] for t in ordinary if t["fade_ease_out_fit"]),
        "slide_fit_duration_ms": distribution(t["slide_ease_out_fit"]["duration_ms"] for t in ordinary if t["slide_ease_out_fit"]),
        "fade_fit_onset_after_request_ms": distribution(t["fade_ease_out_fit"]["onset_after_request_ms"] for t in ordinary if t["fade_ease_out_fit"]),
        "slide_fit_onset_after_request_ms": distribution(t["slide_ease_out_fit"]["onset_after_request_ms"] for t in ordinary if t["slide_ease_out_fit"]),
        "fit_max_residual_ms": max([0.0] + [t[name]["residual_max_ms"] for t in ordinary for name in ("fade_ease_out_fit", "slide_ease_out_fit") if t[name]]),
        "attached_page_max_scale_error": scale_error,
        "toolbar_bounds_span_pt": dict(zip(("x", "y", "width", "height"), toolbar_spans)),
        "display_link_interval_ms": interval_stats,
        "intervals_over_1_5x_median": sum(t > interval_stats["median"] * 1.5 for t in intervals),
        "paired_30pt_travel_max_error": max([0.0] + [t["paired_30pt_travel_max_error"] for t in ordinary]),
        "orthogonal_motion_max_pt": max([0.0] + [t["orthogonal_motion_max_pt"] for t in ordinary]),
        "snapshot_sample_count": sum(s["usesSnapshot"] for s in samples),
    }
    return {"file": str(path), "label": data["label"], "axis": axis, "summary": summary,
            "ordinary": ordinary, "interrupted": interrupted}


def comparison(runs):
    pairs = []
    for axis in ("horizontal", "vertical"):
        baseline = next((r for r in runs if r["axis"] == axis and r["label"].startswith("baseline")), None)
        candidate = next((r for r in runs if r["axis"] == axis and r["label"].startswith("candidate")), None)
        if baseline is None or candidate is None:
            continue
        deltas = {}
        for key in ("fade_fit_duration_ms", "slide_fit_duration_ms", "first_observed_motion_after_request_ms", "display_link_interval_ms"):
            a, b = baseline["summary"][key], candidate["summary"][key]
            deltas[key] = None if a is None or b is None else b["median"] - a["median"]
        pairs.append({"axis": axis, "baseline": baseline["label"], "candidate": candidate["label"],
                      "candidate_minus_baseline_median_ms": deltas,
                      "interpretation": "Duration agreement supports equivalent timing. Callback or request-latency differences alone do not demonstrate a motion-quality or performance advantage."})
    return pairs


def rounded(value):
    if isinstance(value, float):
        return round(value, 4)
    if isinstance(value, dict):
        return {key: rounded(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rounded(item) for item in value]
    return value


def print_table(result):
    print("All times in ms; fitted durations are estimates from presentation samples.")
    print(f"{'Capture':26} {'N':>3} {'Fade':>8} {'Slide':>8} {'First motion':>13} {'Tick p95/max':>16} {'Scale err':>10} {'Bar span':>9} {'Dir bad':>8}")
    for run in result["runs"]:
        summary = run["summary"]
        def median(key):
            value = summary[key]
            return "n/a" if value is None else f"{value['median']:.2f}"
        ticks = summary["display_link_interval_ms"]
        print(f"{run['label']:26} {summary['ordinary_transitions']:3} {median('fade_fit_duration_ms'):>8} {median('slide_fit_duration_ms'):>8} {median('first_observed_motion_after_request_ms'):>13} {ticks['p95']:6.2f}/{ticks['max']:6.2f} {summary['attached_page_max_scale_error']:10.6f} {max(summary['toolbar_bounds_span_pt'].values()):9.4f} {summary['direction_failures']:8}")
    for pair in result["comparisons"]:
        print(f"\n{pair['axis']} candidate − baseline median deltas: " + json.dumps(rounded(pair["candidate_minus_baseline_median_ms"]), sort_keys=True))
    print("\nInterpretation limits:")
    for caveat in CAVEATS:
        print(f"- {caveat}")
    print("\nUse --format json for per-transition endpoint brackets, fits, residuals and interrupted phases.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("captures", nargs="+", type=Path)
    parser.add_argument("--format", choices=("table", "json"), default="table")
    args = parser.parse_args()
    try:
        runs = [analyze_file(path) for path in args.captures]
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    result = {"runs": runs, "comparisons": comparison(runs), "caveats": CAVEATS}
    if args.format == "json":
        print(json.dumps(rounded(result), indent=2, sort_keys=True, allow_nan=False))
    else:
        print_table(result)


if __name__ == "__main__":
    main()
