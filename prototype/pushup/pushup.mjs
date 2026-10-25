// Pure push-up logic: landmarks in, angles / reps / posture feedback out. No DOM, so it runs in node too.

// MediaPipe Pose landmark indices (left, right) per joint.
export const JOINTS = {
  shoulder: [11, 12],
  elbow: [13, 14],
  wrist: [15, 16],
  hip: [23, 24],
  knee: [25, 26],
  ankle: [27, 28],
};

// Easiest first. `up`/`down` are elbow-angle thresholds (deg); `lineRef` is the joint the
// body line (shoulder-hip-X) is measured to; `minLine` is the smallest acceptable body-line angle.
export const VARIATIONS = {
  wall: { label: 'Wall push-up', up: 150, down: 120, lineRef: 'ankle', minLine: 160, gravityLine: false },
  incline: { label: 'Incline push-up (hands on bench)', up: 150, down: 105, lineRef: 'ankle', minLine: 160, gravityLine: true },
  knee: { label: 'Knee push-up', up: 150, down: 100, lineRef: 'knee', minLine: 160, gravityLine: true },
  standard: { label: 'Standard push-up', up: 150, down: 95, lineRef: 'ankle', minLine: 165, gravityLine: true },
};

export function angle(a, b, c) {
  const v1 = [a.x - b.x, a.y - b.y];
  const v2 = [c.x - b.x, c.y - b.y];
  const n = Math.hypot(...v1) * Math.hypot(...v2);
  if (!n) return NaN;
  const cos = (v1[0] * v2[0] + v1[1] * v2[1]) / n;
  return (Math.acos(Math.max(-1, Math.min(1, cos))) * 180) / Math.PI;
}

// Pick the body side the camera sees best (side-on view: one side is mostly hidden).
export function pickSide(lm) {
  const vis = (i) => lm[i]?.visibility ?? 0;
  const score = (s) => ['shoulder', 'elbow', 'wrist', 'hip', 'knee', 'ankle'].reduce((t, j) => t + vis(JOINTS[j][s]), 0);
  return score(0) >= score(1) ? 0 : 1;
}

// aspect = image width / height. MediaPipe x and y are normalized separately, so x is scaled by it to get
// square units before measuring angles; without it a horizontal body on a wide video looks more bent.
export function measure(lm, side, variation, aspect = 1) {
  const cfg = VARIATIONS[variation];
  const p = (j) => { const q = lm[JOINTS[j][side]]; return { x: q.x * aspect, y: q.y, visibility: q.visibility }; };
  const [sh, el, wr, hip, ref] = [p('shoulder'), p('elbow'), p('wrist'), p('hip'), p(cfg.lineRef)];
  const elbow = angle(sh, el, wr);
  const line = angle(sh, hip, ref);
  // Signed hip offset from the shoulder->ref line, as a fraction of torso length. Image y grows downward,
  // so positive = hip lower than the line = sagging, negative = hips piking up.
  const t = ((hip.x - sh.x) * (ref.x - sh.x) + (hip.y - sh.y) * (ref.y - sh.y)) / (((ref.x - sh.x) ** 2 + (ref.y - sh.y) ** 2) || 1);
  const projY = sh.y + t * (ref.y - sh.y);
  const torso = Math.hypot(hip.x - sh.x, hip.y - sh.y) || 1;
  const hipDrop = (hip.y - projY) / torso;
  const minVis = Math.min(sh.visibility ?? 0, el.visibility ?? 0, wr.visibility ?? 0, hip.visibility ?? 0, ref.visibility ?? 0);
  return { elbow, line, hipDrop, minVis };
}

export function postureIssue(m, variation, minLine) {
  const cfg = VARIATIONS[variation];
  if (m.line >= (minLine ?? cfg.minLine)) return null;
  if (!cfg.gravityLine) return 'Keep your body in one straight line';
  return m.hipDrop > 0 ? 'Hips sagging: squeeze your core and glutes' : 'Hips too high: lower them into a straight line';
}

// Personal rule from a trained profile (`baselines` = this user's good reps). It only tightens how a rep is judged
// (good form + cues); whether a rep counts still follows the default depth line. It is never looser than the default,
// and only exists for standard push-ups, the movement the history was recorded for.
export const PERSONAL = { k: 3, minElbowSpread: 3, minLineSpread: 2, minGoodReps: 30 };
const round1 = (x) => Math.round(x * 10) / 10;
export function personalRule(profile, variation = 'standard') {
  const b = profile?.baselines;
  if (variation !== 'standard' || !b || !(b.goodReps >= PERSONAL.minGoodReps)) return null;
  if (![b.elbow?.typical, b.elbow?.spread, b.body_line?.typical, b.body_line?.spread].every(Number.isFinite)) return null;
  const cfg = VARIATIONS.standard;
  const warnElbow = Math.min(cfg.down, round1(b.elbow.typical + PERSONAL.k * Math.max(b.elbow.spread, PERSONAL.minElbowSpread)));
  const minLine = Math.max(cfg.minLine, Math.min(178, round1(b.body_line.typical - PERSONAL.k * Math.max(b.body_line.spread, PERSONAL.minLineSpread))));
  return { warnElbow, minLine, goodReps: b.goodReps };
}

export class RepCounter {
  constructor(variation = 'wall') {
    this.personal = null; // personalRule() output, or null for the default rule
    this.setVariation(variation);
  }

  setPersonal(rule) {
    this.personal = rule;
  }

  setVariation(variation) {
    this.variation = variation;
    this.reset();
  }

  reset() {
    this.reps = [];
    this.state = 'unknown'; // unknown -> up <-> down
    this.elbow = null;
    this.line = null;
    this.hipDrop = 0;
    this.#resetRep();
  }

  #resetRep() {
    this.minElbow = 180;
    this.minLine = 180;
    this.worstDrop = 0;
    this.sawIssue = null;
  }

  // m = measure(...) output, t = clock in seconds (optional, only used for rep timing);
  // returns the rep record when a rep completes, else null.
  update(m, t = null) {
    if (m.minVis < 0.5 || Number.isNaN(m.elbow)) return null;
    const cfg = VARIATIONS[this.variation];
    // Light smoothing: landmarks jitter frame to frame.
    const a = 0.5;
    this.elbow = this.elbow == null ? m.elbow : a * m.elbow + (1 - a) * this.elbow;
    this.line = this.line == null ? m.line : a * m.line + (1 - a) * this.line;
    this.hipDrop = a * m.hipDrop + (1 - a) * this.hipDrop;

    if (this.state === 'unknown') {
      if (this.elbow >= cfg.up) this.state = 'up';
      return null;
    }
    if (this.state === 'up' && this.elbow < cfg.up - 10) {
      this.state = 'down'; // lowering started
      this.#resetRep();
      this.startT = t;
    }
    if (this.state === 'down') {
      this.minElbow = Math.min(this.minElbow, this.elbow);
      if (this.line < this.minLine) {
        this.minLine = this.line;
        this.worstDrop = this.hipDrop;
      }
      if (this.elbow >= cfg.up) {
        this.state = 'up';
        return this.#finish(cfg, t);
      }
    }
    return null;
  }

  #finish(cfg, t) {
    const reachedDepth = this.minElbow <= cfg.down;
    const straight = this.minLine >= cfg.minLine;
    const worst = { line: this.minLine, hipDrop: this.worstDrop };
    // The default judgement is always kept (baseGood / baseIssue): it is what gets saved for training, so a
    // personal rule never trains on its own labels.
    const baseIssue = !reachedDepth
      ? 'Not low enough: bend your elbows more'
      : straight
        ? null
        : postureIssue(worst, this.variation);
    let issue = baseIssue;
    const p = this.personal;
    if (p && reachedDepth) {
      if (this.minLine < p.minLine) issue = postureIssue(worst, this.variation, p.minLine);
      else if (this.minElbow > p.warnElbow) issue = `Shallower than your usual: ${Math.round(this.minElbow)}° (your limit ${p.warnElbow}°)`;
    }
    const rep = {
      n: this.reps.filter((r) => r.counted).length + (reachedDepth ? 1 : 0),
      counted: reachedDepth,
      good: reachedDepth && !issue,
      baseGood: reachedDepth && straight,
      baseIssue,
      minElbow: Math.round(this.minElbow),
      minLine: Math.round(this.minLine),
      secs: t != null && this.startT != null && t >= this.startT ? Math.round((t - this.startT) * 10) / 10 : null, // lowering start -> back up
      issue,
    };
    this.reps.push(rep);
    return rep;
  }

  get count() {
    return this.reps.filter((r) => r.counted).length;
  }

  get goodCount() {
    return this.reps.filter((r) => r.good).length;
  }
}
