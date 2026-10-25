const TEXT = Object.freeze({
  good: 'Rep recorded.',
  'form-warning': 'Check your setup and use a comfortable range.',
  slow: 'Your last rep was slower. Pause if you need to.',
  stop: 'Stop and rest if you feel discomfort.',
});
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const identity = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 128;
const time = value => Number.isFinite(value) && value >= 0 && value <= 1e12;
const validScope = scope => object(scope) && ['ownerId', 'sessionId', 'generation'].every(key => identity(scope[key]));
const validRep = record => object(record) && typeof record.counted === 'boolean' && typeof record.good === 'boolean'
  && (!record.good || record.counted)
  && (!record.counted || (Number.isSafeInteger(record.n) && record.n > 0))
  && (record.secs == null || (Number.isFinite(record.secs) && record.secs > 0))
  && (record.faults == null || (Array.isArray(record.faults) && record.faults.length <= 16
    && record.faults.every(fault => typeof fault === 'string' && fault.length <= 160)));

const validEnvelope = event => object(event) && identity(event.id) && validScope(event.scope)
  && ['pushUp', 'squat'].includes(event.exercise) && ['camera', 'replay', 'fixture'].includes(event.source) && time(event.atMs);

function validateEnvelope(event) {
  if (!validEnvelope(event)) throw new TypeError('Invalid CV event provenance.');
}

export function repFeedback({ id, scope, exercise, source, atMs, record }) {
  validateEnvelope({ id, scope, exercise, source, atMs });
  if (!validRep(record)) throw new TypeError('Invalid accepted rep facts.');
  const feedback = !record.good ? 'form-warning' : record.faults?.includes('slow ascent') ? 'slow' : 'good';
  return {
    version: 1, id, scope: { ...scope }, exercise, source, atMs, expiresAtMs: atMs + 3000,
    feedback, text: TEXT[feedback],
    rep: { number: record.counted ? record.n : null, counted: record.counted, good: record.good, durationSeconds: record.secs ?? null },
  };
}

export function stopFeedback({ id, scope, exercise, source, atMs }) {
  validateEnvelope({ id, scope, exercise, source, atMs });
  return { version: 1, id, scope: { ...scope }, exercise, source, atMs,
    expiresAtMs: null, rep: null, feedback: 'stop', text: TEXT.stop };
}

const PRIORITY = Object.freeze({ good: 0, slow: 1, 'form-warning': 2, stop: 3 });

function validEvent(event) {
  if (!validEnvelope(event) || event.version !== 1 || !Object.hasOwn(TEXT, event.feedback) || event.text !== TEXT[event.feedback]) return false;
  if (event.feedback === 'stop') return event.rep === null && event.expiresAtMs === null;
  const rep = event.rep;
  return object(rep) && validRep({ n: rep.number, counted: rep.counted, good: rep.good, secs: rep.durationSeconds })
    && (rep.counted || rep.number === null) && rep.durationSeconds !== undefined
    && (event.feedback === 'form-warning' ? !rep.good : rep.good)
    && event.expiresAtMs === event.atMs + 3000;
}

export function selectFeedback({ events, context, nowMs }) {
  if (!Array.isArray(events) || !time(nowMs) || context?.phase !== 'active' || !validScope(context.scope)) return null;
  if (context.source === 'camera' && context.cameraOptIn !== true) return null;
  const current = events.filter(event => validEvent(event) && event.source === context.source && event.exercise === context.exercise
    && ['ownerId', 'sessionId', 'generation'].every(key => event.scope[key] === context.scope[key])
    && event.atMs <= nowMs && (event.expiresAtMs === null || nowMs < event.expiresAtMs));
  return current.reduce((best, event) => !best || PRIORITY[event.feedback] > PRIORITY[best.feedback]
    || (event.feedback === best.feedback && event.atMs > best.atMs) ? event : best, null);
}
