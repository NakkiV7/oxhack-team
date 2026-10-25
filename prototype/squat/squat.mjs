// Pure squat logic: landmarks in, hip travel / depth / lean / knee / balance and reps out. No DOM, so it runs in node too.
// A line-for-line port of squat/squat.py (the Python reference, validated on 16 clips); keep the two in step.

// MediaPipe Pose landmark indices (left, right) per joint.
export const JOINTS = { shoulder: [11, 12], hip: [23, 24], knee: [25, 26], ankle: [27, 28] };

// `depthGood` / `depthWarn`: hip below the knee, in thigh lengths, at the bottom of the rep (0 = hip crease level
// with the knee, negative = above). Counting is the same for every variation; only the depth judgement differs.
export const VARIATIONS = {
  standard: { label: 'Bodyweight squat (to parallel)', depthGood: -0.1, depthWarn: -0.35 },
  half: { label: 'Half squat (shallow depth allowed)', depthGood: -0.35, depthWarn: -0.6 },
};

export const GREEN = 0, AMBER = 1, RED = 2;
const VIS = 0.5;                  // landmark visibility needed to trust a joint
const ALPHA = 0.5;                // EMA on measured signals (landmarks jitter frame to frame)
const START = 0.15, END = 0.08;   // hip travel (fraction of leg length) that starts / ends a rep
const MIN_DROP = 0.22;            // smaller max travel = a dip: listed, not counted
const MIN_DUR = 0.5, MAX_DUR = 15;
const FAST_DESCENT_S = 0.45, SLOW_ASCENT_S = 2.2;

// Metrics judged on each rep's worst frame. `view` says where the metric is meaningful; depth limits come from the variation.
export const METRICS = {
  depth: { label: 'Depth', view: 'both', fault: 'shallow', cue: 'Deeper: hips to knee height' },
  lean: { label: 'Lean', view: 'side', good: 40, warn: 55, fault: 'forward lean', cue: 'Chest up' },
  knees: { label: 'Knees', view: 'front', good: 0.85, warn: 0.7, fault: 'knees in', cue: 'Knees out' },
  balance: { label: 'Balance', view: 'front', good: 12, warn: 18, fault: 'uneven', cue: 'Even weight on both feet' },
};
const AGG = { depth: Math.max, lean: Math.max, knees: Math.min, balance: Math.max }; // how a metric accumulates over a rep
const SMOOTHED = ['hipY', 'kneeY', 'thigh', 'height', 'knee', 'kneeMax', 'lean', 'knees', 'balance'];

export function angle(a, b, c) {
  const v1 = [a.x - b.x, a.y - b.y], v2 = [c.x - b.x, c.y - b.y];
  const n = Math.hypot(...v1) * Math.hypot(...v2);
  if (!n) return NaN;
  return (Math.acos(Math.max(-1, Math.min(1, (v1[0] * v2[0] + v1[1] * v2[1]) / n))) * 180) / Math.PI;
}

// (good, warn): lower is better when good <= warn, else higher is better.
export function grade(good, warn, x) {
  if (good <= warn) return x <= good ? GREEN : x <= warn ? AMBER : RED;
  return x >= good ? GREEN : x >= warn ? AMBER : RED;
}

const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const deg = (r) => (r * 180) / Math.PI;
const median = (a) => { const s = [...a].sort((x, y) => x - y); return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2; };

// aspect = image width / height: MediaPipe x and y are normalized separately, so x is scaled to square units first.
function points(lm, aspect) {
  return (i) => ({ x: lm[i].x * aspect, y: lm[i].y, v: lm[i].visibility ?? 0 });
}

export function measure(lm, aspect = 1) {
  const p = points(lm, aspect);
  const legs = [0, 1].map((s) => [p(JOINTS.hip[s]), p(JOINTS.knee[s]), p(JOINTS.ankle[s])]);
  const seen = legs.map(([, k, a]) => Math.min(k.v, a.v) >= VIS);        // MediaPipe extrapolates joints just off-frame
  const side = Math.min(...legs[0].map((q) => q.v)) >= Math.min(...legs[1].map((q) => q.v)) ? 0 : 1;
  const [hip, knee, ank] = legs[side];                                      // best-seen leg (a side view hides one)
  const shoL = p(JOINTS.shoulder[0]), shoR = p(JOINTS.shoulder[1]), hipL = legs[0][0], hipR = legs[1][0];
  const sho = { x: (shoL.x + shoR.x) / 2, y: (shoL.y + shoR.y) / 2 };
  const feet = seen[side];
  const kneesIn = Math.max(legs[0][1].y, legs[1][1].y) < 1.05;             // knee metrics need real, in-frame joints
  const feetIn = Math.max(legs[0][2].y, legs[1][2].y) < 1.05;
  const angles = legs.filter((_, i) => seen[i]).map(([h, k, a]) => angle(h, k, a)); // 2D: a straight leg is collinear from any view
  const up = { x: sho.x - hip.x, y: sho.y - hip.y };
  const tilt = (a, b) => deg(Math.atan2(Math.abs(a.y - b.y), Math.abs(a.x - b.x) + 1e-6));
  return {
    hipsOk: Math.min(hip.v, knee.v) >= VIS && hip.y > 0 && hip.y < 1.1,   // a hallucinated hip below the frame is not a squat
    feetOk: feet, kneesIn, feetIn, side,
    hipY: hip.y, kneeY: knee.y, thigh: dist(hip, knee),
    height: feet ? ank.y - hip.y : NaN,                                     // hip height above the ankle
    knee: angles.length ? Math.min(...angles) : NaN,                        // straightest-leg gate uses the most bent seen leg
    kneeMax: angles.length ? Math.max(...angles) : NaN,
    lean: deg(Math.atan2(Math.abs(up.x), -up.y + 1e-6)),                    // torso from vertical
    knees: feet && kneesIn && feetIn ? Math.abs(legs[0][1].x - legs[1][1].x) / (Math.abs(legs[0][2].x - legs[1][2].x) + 1e-6) : 1,
    balance: Math.abs(tilt(hipL, hipR) - tilt(shoL, shoR)),                 // perspective tilts both the same; weight shift does not
    facing: Math.abs(shoL.x - shoR.x) / (dist(sho, hip) + 1e-6),
  };
}

export class RepCounter {
  constructor(variation = 'standard') { this.setVariation(variation); }

  setVariation(variation) { this.variation = variation; this.reset(); }

  reset() {
    this.reps = [];              // counted reps and not-counted attempts, in order (see `counted`)
    this.dips = 0;
    this.state = 'standing';     // standing -> down -> up -> standing
    this.view = 'front';
    this.facing = 1;
    this.s = null;               // smoothed signals
    this.base = null;            // standing reference: hipY, height, thigh
    this.cur = {};               // worst metric values in the current rep
    this.maxDrop = 0;
    this.tStart = this.tBottom = 0;
    this.lost = null;
    this.recent = [];            // [t, drop] over the last 3 s
    this.drop = 0; this.warn = ''; this.valid = new Set();
    this.live = { depth: null, lean: null, knees: null, balance: null };
    this.grades = { depth: GREEN, lean: GREEN, knees: GREEN, balance: GREEN };
    this.segments = { torso: GREEN, thigh: GREEN, shin: GREEN, knees: GREEN };
    this.cue = null;             // { text, tone, until }
  }

  get count() { return this.reps.filter((r) => r.counted).length; }
  get goodCount() { return this.reps.filter((r) => r.good).length; }
  cueText(t) { return this.cue && t < this.cue.until ? this.cue : null; }

  #grade(k, x) {
    const v = VARIATIONS[this.variation];
    return k === 'depth' ? grade(v.depthGood, v.depthWarn, x) : grade(METRICS[k].good, METRICS[k].warn, x);
  }
  #say(text, tone, t, hold = 2.5) { this.cue = { text, tone, until: t + hold }; }

  // lm = MediaPipe landmarks (33, normalized), t = clock in seconds, aspect = width / height.
  // Returns the rep record when an attempt finishes (counted or not), else null. Live fields are updated every call.
  update(lm, t, aspect = 1) {
    const m = measure(lm, aspect);
    this.facing = 0.9 * this.facing + 0.1 * m.facing;           // two thresholds: hold the last view in between
    if (this.facing > 0.5) this.view = 'front'; else if (this.facing < 0.35) this.view = 'side';
    this.warn = m.kneesIn && m.feetIn ? '' : 'Step back so your knees and feet are in view (counting only)';
    if (!m.hipsOk) {
      this.lost ??= t;
      if (this.state !== 'standing' && t - this.lost > 1) this.state = 'standing';   // tracking gone for a second: abandon the rep
      this.#frame(m, 0, 'Step back: hips and knees must be in view');
      return null;
    }
    this.lost = null;

    const smooth = (n, o) => (Number.isNaN(n) ? o : Number.isNaN(o) ? n : ALPHA * n + (1 - ALPHA) * o);
    const s = { ...m };
    if (this.s) for (const k of SMOOTHED) s[k] = smooth(m[k], this.s[k]);
    this.s = s;
    const kneeKnown = !Number.isNaN(s.knee);
    this.base ??= { hipY: s.hipY, height: s.height, thigh: s.thigh };
    const leg = Number.isNaN(this.base.height) ? 2 * this.base.thigh : this.base.height;
    // Hip travel: hip height above the ankle when feet are seen (camera motion cancels), else hip pixel y.
    let drop = kneeKnown ? 1 - s.height / leg : (s.hipY - this.base.hipY) / leg;
    if (Number.isNaN(drop)) drop = (s.hipY - this.base.hipY) / leg;
    s.depth = (s.hipY - s.kneeY) / this.base.thigh;
    const straight = kneeKnown ? s.knee > 160 : drop < END;     // every seen leg straight
    const bending = kneeKnown ? s.kneeMax < 150 : true;         // every seen leg bent (a leg lift is not a squat)
    this.recent = this.recent.filter(([t0]) => t - t0 <= 3).concat([[t, drop]]);
    const vals = this.recent.map(([, d]) => d);
    const parked = t - this.recent[0][0] >= 3 && Math.max(...vals) - Math.min(...vals) < 0.05; // hardly moved for 3 s
    const valid = new Set(Object.keys(METRICS).filter((k) => METRICS[k].view === 'both' || METRICS[k].view === this.view));
    if (!(m.kneesIn && m.feetIn)) { valid.delete('depth'); valid.delete('knees'); } // depth / knee tracking need real joints
    this.valid = valid;
    let rep = null;

    if (this.state === 'standing') {
      if (straight || parked) {                                  // re-baseline: moved, zoomed, bad first frame, or just standing there
        for (const k of Object.keys(this.base)) this.base[k] = 0.9 * this.base[k] + 0.1 * s[k];
      } else if (drop > START && bending) {
        this.state = 'down'; this.tStart = t; this.maxDrop = drop;
        this.cur = { depth: s.depth, lean: s.lean, knees: s.knees, balance: s.balance };
      }
    } else if (t - this.tStart > MAX_DUR) {                      // stuck: assume they are standing now and start over
      this.state = 'standing';
      this.base = { hipY: s.hipY, height: s.height, thigh: s.thigh };
    } else {
      for (const k of Object.keys(this.cur)) this.cur[k] = AGG[k](this.cur[k], s[k]);
      this.maxDrop = Math.max(this.maxDrop, drop);
      if (this.state === 'down' && drop < this.maxDrop - 0.04 && this.maxDrop > 0.1) { this.state = 'up'; this.tBottom = t; }
      else if (this.state === 'up' && (drop < END || (straight && drop < 0.3 * this.maxDrop))) rep = this.#finish(t, valid);
    }

    if (this.state === 'up' && this.cur.lean <= 65) {            // live faults on the way up, unless it's a hinge
      for (const k of ['lean', 'knees']) if (valid.has(k) && this.#grade(k, this.cur[k]) === RED) this.#say(METRICS[k].cue, 'bad', t);
    }
    this.#frame(m, drop, this.warn);
    return rep;
  }

  #finish(t, valid) {
    this.state = 'standing';
    const down = this.tBottom - this.tStart, up = t - this.tBottom;
    const { lean, depth } = this.cur;
    const hinge = valid.has('lean') && (lean > 80 || (lean > 60 && depth < -0.3));   // bent over without sitting down
    if (this.maxDrop > 0.9 || hinge || lean > 100) return null;                       // camera cut, pick-up / hinge, garbage pose
    const secs = Math.round((down + up) * 10) / 10;
    if (this.maxDrop < MIN_DROP || down + up < MIN_DUR || down + up > MAX_DUR) {
      if (this.maxDrop < MIN_DROP / 2) return null;                                   // a wobble, not an attempt
      this.dips += 1;
      const rep = { counted: false, good: false, issue: 'Not low enough: hips to knee height', secs, travel: this.maxDrop, faults: ['shallow'] };
      this.reps.push(rep);
      this.#say('Go lower', 'warn', t);
      return rep;
    }
    const grades = {};
    for (const k of valid) grades[k] = this.#grade(k, this.cur[k]);
    const faults = [...valid].filter((k) => grades[k] >= AMBER).map((k) => METRICS[k].fault);
    const earlier = this.reps.filter((r) => r.counted).map((r) => r.tUp);
    const slow = up > SLOW_ASCENT_S || (earlier.length >= 2 && up > 1.6 * median(earlier));
    if (down < FAST_DESCENT_S) faults.push('fast descent');
    if (slow) faults.push('slow ascent');
    const worst = [...valid].sort((a, b) => grades[b] - grades[a])[0];
    const issue = worst && grades[worst] >= AMBER ? METRICS[worst].cue : slow ? "You're slowing down" : null;
    const rep = {
      n: this.count + 1, counted: true, good: !faults.some((f) => !['fast descent', 'slow ascent'].includes(f)), issue, faults, secs,
      tDown: Math.round(down * 10) / 10, tUp: Math.round(up * 10) / 10, travel: Math.round(this.maxDrop * 100) / 100,
      depth: Math.round(this.cur.depth * 100) / 100, lean: Math.round(this.cur.lean), knees: Math.round(this.cur.knees * 100) / 100,
      balance: Math.round(this.cur.balance), grades,
    };
    this.reps.push(rep);
    if (issue) this.#say(issue, worst && grades[worst] === RED ? 'bad' : 'warn', t);
    else if (down < FAST_DESCENT_S) this.#say('Control the way down', 'warn', t);
    return rep;
  }

  #frame(m, drop, warn) {
    const last = [...this.reps].reverse().find((r) => r.counted);
    const ref = this.state !== 'standing' ? this.cur : last ? { depth: last.depth, lean: last.lean, knees: last.knees, balance: last.balance } : null;
    for (const k of Object.keys(METRICS)) this.grades[k] = ref && this.valid.has(k) ? this.#grade(k, ref[k]) : GREEN;
    this.segments = { thigh: this.grades.depth, shin: this.grades.depth, knees: this.grades.knees,
      torso: this.view === 'side' ? this.grades.lean : this.grades.balance };
    const src = this.s && 'depth' in this.s ? this.s : { ...m, depth: null };
    for (const k of Object.keys(METRICS)) this.live[k] = this.valid.has(k) ? src[k] : null;
    this.drop = drop; this.warn = warn; this.side = m.side;
  }
}
