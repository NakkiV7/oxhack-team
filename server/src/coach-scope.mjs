const chest = /\bchest (?:pain|hurts?)\b/i;
const negated = /\b(?:no|without|not have|don't have|do not have|no longer have) chest pain\b|\b(?:pain (?:is |has )?(?:gone|resolved)|none now)\b/i;
const past = /\b(?:yesterday|last (?:week|month|year)|previous|had|used to)\b/i;
const educational = /^(?:what does|explain (?:the|this)|what is|what are)|["“][^"”]*chest (?:pain|hurts?)/i;

export function coachScope(message = '') {
  const text = message.trim();
  const unquoted = text.replace(/"[^"\n]*"|“[^”\n]*”/g, ' ');
  const observations = unquoted.split(/[.!?;,]+|\b(?:but|however|and|although)\b/i)
    .map(clause => clause.trim())
    .filter(clause => chest.test(clause) && /\b(?:I|my)\b/i.test(clause) && !educational.test(clause));
  const current = observations.some(clause => !negated.test(clause) &&
    (!past.test(clause) || /\b(?:still|right now|currently)\b/i.test(clause)));
  if (current) return 'urgent';
  if (observations.some(clause => past.test(clause)) && /\b(?:safe|exercise|workout|train)\b/i.test(text)) return 'medical';
  if (/\b(?:diagnos\w*|prescri\w*|medication dose|dosage|rehabilitation (?:plan|workout)|rehab (?:plan|workout))\b/i.test(text)) return 'medical';
  if (/\b(?:write|debug|generate)\b.*\b(?:python|javascript|sql|code|poem|essay)\b|\b(?:stock trading|investment advice|cryptocurrency)\b/i.test(text)) return 'unrelated';
  return null;
}

export function scopeGuidance(reason) { return [reason === 'urgent' ? 'nhs-chest-pain' : 'nhs-strength']; }
export function scopeMessage(reason) {
  if (reason === 'urgent') return 'Stop exercising. If chest pain is sudden or does not go away, or comes with sweating, sickness, light-headedness or breathlessness, call 999. This is general NHS guidance, not a diagnosis. https://www.nhs.uk/symptoms/chest-pain/';
  if (reason === 'medical') return 'I can offer general exercise guidance, but cannot diagnose or prescribe treatment or a rehabilitation plan. Ask a qualified healthcare professional about symptoms or a medical condition before planning exercise.';
  return 'I can help with Spottr, exercise planning and your recorded training. Ask a training question to continue.';
}
