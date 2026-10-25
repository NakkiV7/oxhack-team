"""Figures for the paper from the evaluation artifact and the stored demo workout. Nothing is refitted here.
Run from prototype/squat/docs/hrt-paper:  ../../../../.venv/bin/python make_figures.py
"""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
import sys
KEY = sys.argv[1] if len(sys.argv) > 1 else "relative"  # which target's artifact to render
R = json.loads((HERE / f"../../hrt/results-{KEY}.json").read_text())
dev = R.get("dev")
plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 150})
BLUE, ORANGE, GREEN, GREY, RED = "#0a84ff", "#ff9f0a", "#30d158", "#8e8e93", "#ff453a"

if dev:
    # Reliability diagram with bin counts.
    bins = [b for b in dev["reliability"]["full"] if b["n"]]
    fig, ax = plt.subplots(figsize=(3.2, 3.0))
    ax.plot([0, 1], [0, 1], "--", color=GREY, lw=0.8)
    ax.scatter([b["meanP"] for b in bins], [b["observed"] for b in bins], s=[20 + 6 * b["n"] for b in bins], color=BLUE, alpha=0.8)
    for b in bins:
        ax.annotate(f"n={b['n']}", (b["meanP"], b["observed"]), textcoords="offset points", xytext=(0, 8), ha="center", fontsize=8)
    ax.set(xlim=(0, 1), ylim=(0, 1), xlabel="predicted probability (out of fold)", ylabel="observed event rate")
    fig.tight_layout(); fig.savefig(HERE / f"fig_reliability-{KEY}.pdf"); plt.close(fig)

    # Decision frontier: recall against false alerts per set, budget line, heuristic and silent policies.
    fr = [p for p in dev["frontier"]["full"] if p["recall"] is not None]
    fig, ax = plt.subplots(figsize=(3.4, 3.0))
    ax.plot([p["falseAlertsPerSet"] for p in fr], [p["recall"] for p in fr], "-o", color=BLUE, ms=3, lw=1, label="logistic model, thresholds")
    ax.axvline(R["budget"], color=ORANGE, ls="--", lw=0.8, label=f"budget {R['budget']} false alerts/set")
    h, s = dev["policies"]["heuristic"], dev["policies"]["silent"]
    ax.plot(h["falseAlertsPerSet"], h["recall"], "s", color=GREEN, label="existing slow-ascent rule")
    ax.plot(s["falseAlertsPerSet"], s["recall"], "x", color=GREY, label="always silent")
    sel = dev["policies"].get("full")
    if sel:
        ax.plot(sel["falseAlertsPerSet"], sel["recall"], "o", color=BLUE, ms=9, mfc="none", label=f"selected $\\tau$={sel['tau']}")
    ax.set(xlabel="false alerts per monitored set", ylabel="event recall", ylim=(-0.02, 1.02))
    ax.legend(fontsize=7, loc="upper right")
    fig.tight_layout(); fig.savefig(HERE / f"fig_frontier-{KEY}.pdf"); plt.close(fig)

    # Brier by model with the bootstrap interval of the primary difference drawn as text.
    ab = dev["ablations"]
    names, vals = ["constant", "set position", "tempo", "tempo + pose"], [ab["constant"]["brier"], ab["position"]["brier"], ab["tempo"]["brier"], ab["full"]["brier"]]
    fig, ax = plt.subplots(figsize=(3.4, 2.6))
    ax.bar(names, vals, color=[GREY, GREY, BLUE, BLUE])
    for i, v in enumerate(vals):
        ax.text(i, v + 0.01, f"{v:.3f}", ha="center", fontsize=8)
    ax.set(ylabel="Brier score (lower is better)", ylim=(0, max(vals) * 1.25))
    ax.tick_params(axis="x", labelsize=8)
    fig.tight_layout(); fig.savefig(HERE / f"fig_brier-{KEY}.pdf"); plt.close(fig)

# Forecast and outcome timeline of the stored demo replay, if exported.
demo = HERE / "demo-review.json"
if demo.exists():
    D = json.loads(demo.read_text())
    rows = [r for r in D["rows"] if r.get("probability") is not None]
    reps = D["reps"]
    first = [r["down_secs"] for r in reps if r["counted"]][:3]; base = sorted(first)[len(first) // 2] if first else None
    L, U = (R["target"]["L"], R["target"]["U"]) if "L" in R["target"] else (round(base * 0.75, 2), round(base * 1.25, 2))
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(4.6, 3.6), sharex=True, gridspec_kw={"height_ratios": [1.3, 1]})
    xs = [r["rep_n"] for r in reps if r["counted"]]
    a1.axhspan(L, U, color=GREEN, alpha=0.12, label=f"target {L}–{U} s")
    a1.plot(xs, [r["down_secs"] for r in reps if r["counted"]], "o-", color=BLUE, ms=4, label="lowering duration")
    a1.set(ylabel="seconds"); a1.legend(fontsize=7, loc="upper left")
    for r in rows:
        a2.plot(r["rep_n"], r["probability"], "o", color=ORANGE if r["action"] == "cue" else BLUE)
        if r.get("outcome") == 1:
            a2.annotate("", xy=(r["rep_n"] + r["onset_offset"], r["probability"]), xytext=(r["rep_n"], r["probability"]), arrowprops=dict(arrowstyle="->", color=RED, lw=0.8))
            a1.axvline(r["rep_n"] + r["onset_offset"], color=RED, ls=":", lw=0.8)
    if rows and rows[0].get("threshold") is not None:
        a2.axhline(rows[0]["threshold"], color=ORANGE, ls="--", lw=0.8, label=f"cue threshold {rows[0]['threshold']}")
    a2.set(xlabel="counted rep", ylabel="forecast p", ylim=(0, 1)); a2.legend(fontsize=7, loc="upper left")
    a2.set_xticks(xs)
    fig.tight_layout(); fig.savefig(HERE / f"fig_timeline-{KEY}.pdf"); plt.close(fig)
print("figures written:", sorted(p.name for p in HERE.glob("fig_*.pdf")))
