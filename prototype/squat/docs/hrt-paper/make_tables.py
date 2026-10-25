"""Generate results.tex (LaTeX macros and table bodies) from ../../hrt/results.json so the paper and the app agree.
Run from prototype/squat/docs/hrt-paper:  ../../../../.venv/bin/python make_tables.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
import sys
KEY = sys.argv[1] if len(sys.argv) > 1 else "relative"  # which target's artifact to render
PREFIX = sys.argv[2] if len(sys.argv) > 2 else ""  # macro prefix, so two targets can be cited in one document
R = json.loads((HERE / f"../../hrt/results-{KEY}.json").read_text())
card, dev, test = R["datasetCard"], R.get("dev"), R.get("test")


def f(v, d=3):
    return "not evaluated" if v is None else (f"{v:.{d}f}" if isinstance(v, (int, float)) else str(v))


def pct(v):
    return "not evaluated" if v is None else f"{100 * v:.0f}\\%"


def ci(c):
    return "not evaluated" if not c or c.get("low") is None else f"{c['mean']:+.3f} [{c['low']:+.3f}, {c['high']:+.3f}]"


macros = {
    "TargetLabel": R["target"]["label"], "TargetL": R["target"].get("L", "--"), "TargetU": R["target"].get("U", "--"), "TargetKey": KEY, "Horizon": R["horizon"], "MinReps": R["minReps"],
    "Budget": R["budget"], "Seed": R["seed"], "LabelVersion": R["labelVersion"], "FeatureVersion": R["featureVersion"], "PolicyVersion": R["policyVersion"],
    "ModelRun": R.get("modelRun", "none"), "DatasetSha": R["datasetSha256"][:12], "GitCommit": (R.get("gitCommit") or "")[:10], "GeneratedAt": R["generatedAt"][:16].replace("T", " "),
    "NPeople": card["people"], "NRecordings": card["recordings"], "NAttempts": card["attempts"], "NCounted": card["countedReps"],
    "NOrigins": card["audit"]["origins"], "NObserved": card["audit"]["observed"], "NPositive": card["audit"]["positives"],
    "NIneligibleBaseline": card["audit"]["ineligible"].get("baseline", 0), "NIneligibleOutside": card["audit"]["ineligible"].get("current_rep_outside_target", 0), "NIneligibleAfter": card["audit"]["ineligible"].get("after_departure", 0),
    "NExcludedEnded": card["audit"]["excluded"].get("set_ended", 0), "NExcludedInvalid": card["audit"]["excluded"].get("invalid_rep_in_horizon", 0),
    "NDevRecordings": card["bySplit"]["dev"]["recordings"], "NDevOrigins": card["bySplit"]["dev"]["eligibleOrigins"], "NDevPositive": card["bySplit"]["dev"]["positives"],
    "NTestRecordings": card["bySplit"]["test"]["recordings"], "NTestOrigins": card["bySplit"]["test"]["eligibleOrigins"], "NTestPositive": card["bySplit"]["test"]["positives"],
    "Status": R["status"], "GroupBy": (R.get("dev") or {}).get("groupBy", "person"), "NPersonGroups": len({v["person"] for v in card["provenance"].values()}),
}
if dev:
    p, pol, ab, bs = dev["probability"], dev["policies"], dev["ablations"], dev["bootstrap"]["intervals"]
    macros.update({
        "DevGroups": dev["groups"], "Prevalence": pct(dev["prevalence"]), "LambdaFull": dev["lambdas"]["full"], "LambdaTempo": dev["lambdas"]["tempo"], "LambdaPosition": dev["lambdas"]["position"],
        "BrierConst": f(p["constant"]["brier"]), "BrierPos": f(p["position"]["brier"]), "BrierTempo": f(p["tempo"]["brier"]), "BrierFull": f(p["full"]["brier"]),
        "LogLossConst": f(p["constant"]["logLoss"]), "LogLossPos": f(p["position"]["logLoss"]), "LogLossTempo": f(p["tempo"]["logLoss"]), "LogLossFull": f(p["full"]["logLoss"]),
        "APConst": f(p["constant"]["averagePrecision"]), "APFull": f(p["full"]["averagePrecision"]),
        "TauFull": f(pol["full"]["tau"], 2) if pol.get("full") else "none", "RecallFull": pct(pol["full"]["recall"]) if pol.get("full") else "none within budget", "FAFull": f(pol["full"]["falseAlertsPerSet"], 2) if pol.get("full") else "--",
        "RecallHeur": pct(pol["heuristic"]["recall"]), "FAHeur": f(pol["heuristic"]["falseAlertsPerSet"], 2), "AlertsHeur": pol["heuristic"]["alerts"], "EventsDev": pol["heuristic"]["events"], "LeadHeur": f(pol["heuristic"]["medianLeadSecs"], 1),
        "CIBrierFullConst": ci(bs["brierFullMinusConstant"]), "CIBrierFullPos": ci(bs["brierFullMinusPosition"]), "CIRecallFullHeur": ci(bs["recallFullMinusHeuristic"]), "CIFAFullHeur": ci(bs["falseAlertsFullMinusHeuristic"]),
        "BootN": dev["bootstrap"]["resamples"], "CalibrationStatus": dev["reliability"]["status"],
        "MAERidge": f(R["regression"]["mae"]["ridgeTempo"], 2), "MAELast": f(R["regression"]["mae"]["lastValue"], 2), "MAEMedian": f(R["regression"]["mae"]["rollingMedian"], 2),
    })
if dev and dev["policies"].get("drift"):
    dr = dev["policies"]["drift"]; bs = dev["bootstrap"]["intervals"]
    deployed = json.loads((HERE / f"../../hrt/model-{KEY}.json").read_text()).get("policy", {}).get("kind") if R.get("modelRun") else None
    macros.update({"DriftTheta": f(dr["theta"], 2), "RecallDrift": pct(dr["recall"]), "FADrift": f(dr["falseAlertsPerSet"], 2), "AlertsDrift": dr["alerts"],
                   "LeadDrift": f(dr["medianLeadSecs"], 1) if dr["medianLeadSecs"] is not None else "--", "LeadDriftReps": dr["medianLeadReps"] if dr["medianLeadReps"] is not None else "--",
                   "CIRecallDriftHeur": ci(bs.get("recallDriftMinusHeuristic")), "CIFADriftHeur": ci(bs.get("falseAlertsDriftMinusHeuristic")),
                   "DeployedPolicy": "the drift rule" if deployed == "drift" else "the logistic threshold"})
if dev and dev["ablations"].get("history"):
    h = dev["ablations"]["history"]
    macros.update({"BrierHist": f(h["brier"]), "LogLossHist": f(h["logLoss"]), "RecallHist": pct(h["recallAtBudget"])})
if R.get("personal"):
    pp = R["personal"][0]  # the person with the most events
    macros.update({"PersonalPerson": pp["person"], "PersonalSets": pp["sets"], "PersonalN": pp["pooled"]["n"], "PersonalPos": pp["pooled"]["positives"], "PersonalBrierHist": f(pp["pooled"]["brierHistory"]),
                   "PersonalBrierFull": f(pp["pooled"]["brierFull"]), "PersonalBrierConst": f(pp["pooled"]["brierConstant"]), "PersonalRecallHist": pct(pp["policy"]["history"]["recall"]), "PersonalFAHist": f(pp["policy"]["history"]["falseAlertsPerSet"], 2),
                   "PersonalRecallHeur": pct(pp["policy"]["heuristic"]["recall"]), "PersonalFAHeur": f(pp["policy"]["heuristic"]["falseAlertsPerSet"], 2),
                   "PersonalRecallDrift": pct(pp["policy"]["drift"]["recall"]), "PersonalFADrift": f(pp["policy"]["drift"]["falseAlertsPerSet"], 2)})
if test:
    tp, tpol = test["probability"], test["policies"]
    macros.update({"TestGroups": test["groups"], "TestPrevalence": pct(test["prevalence"]), "TestBrierConst": f(tp["constant"]["brier"]), "TestBrierFull": f(tp["full"]["brier"]), "TestLogLossFull": f(tp["full"]["logLoss"]),
                   "TestRecallFull": pct(tpol["full"]["recall"]), "TestFAFull": f(tpol["full"]["falseAlertsPerSet"], 2), "TestRecallHeur": pct(tpol["heuristic"]["recall"]), "TestFAHeur": f(tpol["heuristic"]["falseAlertsPerSet"], 2)})

import re
def tex(v):  # escape bare %, & and # in free-text values (already-escaped sequences are left alone)
    return re.sub(r"(?<!\\)([%&#])", r"\\\1", v) if isinstance(v, str) else v
lines = ["% Generated by make_tables.py from hrt/results.json. Do not edit."]
for k, v in macros.items():
    lines.append(f"\\newcommand{{\\{PREFIX}{k}}}{{{tex(v)}}}")
if dev:
    rows = [("A constant (training prevalence)", p["constant"], pol.get("constant")), ("B set position", p["position"], pol.get("position")), ("tempo features", p["tempo"], pol.get("tempo")), ("D tempo + pose (deployed)", p["full"], pol.get("full"))]
    body = [f"{n} & {m['n']} & {f(m['brier'])} & {f(m['logLoss'])} & {f(m['averagePrecision'])} & {pct(q['recall']) if q else 'none'} & {f(q['falseAlertsPerSet'], 2) if q else '--'} \\\\" for n, m, q in rows]
    body.append(f"C slow-ascent rule & {p['full']['n']} & -- & -- & -- & {pct(pol['heuristic']['recall'])} & {f(pol['heuristic']['falseAlertsPerSet'], 2)} \\\\")
    body.append(f"always silent & {p['full']['n']} & -- & -- & -- & {pct(pol['silent']['recall'])} & {f(pol['silent']['falseAlertsPerSet'], 2)} \\\\")
    lines.append("\\newcommand{\\" + PREFIX + "BaselineRows}{" + "\n".join(body) + "}")
    per = [f"{g['group'].replace('_', '\\_')} & {g['n']} & {g['positives']} & {f(g['brierFull'])} & {f(g['brierConstant'])} \\\\" for g in dev["perGroup"]]
    lines.append("\\newcommand{\\" + PREFIX + "PerGroupRows}{" + "\n".join(per) + "}")
    rel = [f"{b['lo']:.1f}--{min(1, b['hi']):.1f} & {b['n']} & {f(b['meanP'], 2)} & {f(b['observed'], 2)} \\\\" for b in dev["reliability"]["full"]]
    lines.append("\\newcommand{\\" + PREFIX + "ReliabilityRows}{" + "\n".join(rel) + "}")
prov = [f"{k.replace('_', '\\_')} & {v['split']} & {v['person'].replace('_', '\\_')} & {v['provenance']} & {v['reps']} \\\\" for k, v in card["provenance"].items()]
lines.append("\\newcommand{\\" + PREFIX + "ProvenanceRows}{" + "\n".join(prov) + "}")
lines.append("\\newcommand{\\" + PREFIX + "LabelDefinition}{" + card["labelDefinition"].replace("_", "\\_") + "}")
(HERE / f"results-{KEY}.tex").write_text("\n".join(lines) + "\n")
print(f"wrote results-{KEY}.tex with {len(macros)} macros; status {R['status']}; test {'present' if test else 'absent'}")
