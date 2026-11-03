import { z } from 'zod';
import { readFileSync } from 'node:fs';

// Training path and camera coaching tasks. Gemini only selects and words: every id, link, number and bound comes from the
// request, which the app builds from its own catalogue and rules, and the app validates the result again before saving.
// Exercises come from the same Swift catalogue the app ships, so a new catalogue entry needs no change here.

const boundedText = max => z.string().max(max).refine(value => value.trim().length > 0);
const hasLink = text => /https?:|www\./i.test(text);

const source = readFileSync(new URL('../../Shared/Core/ExerciseCatalog.swift', import.meta.url), 'utf8');
export const pathCatalog = source.split('\n').filter(line => line.includes('.init(id:')).map(line => {
  const match = line.match(/\.init\(id: "([^"]+)", name: "([^"]+)", family: \.([a-z]+), level: (\d+), goal: (\d+), unit: \.(reps|seconds).*?tracking: (nil|\.[A-Za-z0-9]+)/);
  if (!match) throw Error('Exercise catalogue format changed; update the path catalogue reader.');
  return { id: match[1], name: match[2], family: match[3], level: Number(match[4]), goal: Number(match[5]), unit: match[6], tracked: match[7] !== 'nil' };
});
const ids = pathCatalog.map(item => item.id);
const byID = Object.fromEntries(pathCatalog.map(item => [item.id, item]));
const exerciseID = z.enum(ids);
// Only movements with a camera tracker can be assessed; the rest of the catalogue is practice until a tracker is trained.
const trackedID = z.enum(pathCatalog.filter(item => item.tracked).map(item => item.id));
const unique = list => new Set(list).size === list.length;

// ---------- path proposal ----------
export const pathRequest = z.strictObject({
  generationID: boundedText(128),
  goal: exerciseID,
  answers: z.strictObject({
    band: z.enum(['beginner', 'intermediate', 'advanced', 'unsure']),
    focus: z.enum(['learn', 'consistency', 'improve', 'unsure']).nullable(),
    coachingStyle: z.enum(['concise', 'encouraging', 'explanatory']).nullable(),
    minutesPerSession: z.number().int().min(5).max(120),
    sessionsPerWeek: z.number().int().min(1).max(7)
  }),
  // The exercises this person can use (equipment and left-out movements already removed by the app).
  exercises: z.array(z.strictObject({
    id: exerciseID,
    capability: z.enum(['cameraAssessment', 'cameraCounting', 'practiceLog']),
    allowedPrerequisites: z.array(exerciseID).max(6),
    maxTarget: z.number().int().min(1).max(200)
  })).min(1).max(ids.length),
  allowedStarts: z.array(exerciseID).min(1).max(6),
  ruleStart: exerciseID,
  // Validation errors from the app's first attempt, for one repair request.
  repair: z.array(boundedText(200)).max(12).default([])
}).refine(data => {
  const usable = data.exercises.map(item => item.id);
  return unique(usable) && usable.includes(data.goal) && data.allowedStarts.every(id => usable.includes(id)) && unique(data.allowedStarts)
    && data.allowedStarts.includes(data.ruleStart) && data.exercises.every(item => item.allowedPrerequisites.every(id => usable.includes(id) && id !== item.id))
    && data.exercises.every(item => item.maxTarget <= Math.ceil(byID[item.id].goal * 1.5));
});

export function pathOutputContract(data) {
  const usable = data.exercises.map(item => item.id), allowed = Object.fromEntries(data.exercises.map(item => [item.id, item]));
  const id = z.enum(usable);
  const node = z.strictObject({
    id,
    why: boundedText(240),
    prerequisites: z.array(id).max(4),
    optional: z.boolean(),
    supports: id.nullable(),
    practiceTarget: z.strictObject({ sets: z.number().int().min(1).max(4), target: z.number().int().min(1).max(200), perWeek: z.number().int().min(1).max(6) })
  });
  // A same-family link to a lower level is allowed, as in the app's rules; anything else must be a listed prerequisite.
  const linkAllowed = (child, parent) => allowed[child].allowedPrerequisites.includes(parent)
    || (byID[parent].family === byID[child].family && byID[parent].level < byID[child].level);
  return z.strictObject({
    generationID: z.enum([data.generationID]),
    nodes: z.array(node).min(4).max(6),
    start: z.enum(data.allowedStarts),
    goalNode: id,
    route: z.array(id).min(1).max(6),
    rationale: boundedText(400),
    startReason: boundedText(240),
    emphasis: boundedText(240)
  }).refine(path => {
    const nodeIDs = path.nodes.map(item => item.id);
    // The path ends at the highest level of the goal family's main chain, not necessarily at the goal movement itself.
    const chain = path.nodes.filter(item => !item.optional && byID[item.id].family === byID[data.goal].family);
    const last = chain.reduce((top, item) => (!top || byID[item.id].level > byID[top.id].level ? item : top), null);
    return unique(nodeIDs) && nodeIDs.includes(data.goal) && nodeIDs.includes(path.start) && last?.id === path.goalNode
      && path.route.every(item => nodeIDs.includes(item)) && unique(path.route)
      && path.nodes.filter(item => item.optional).length <= 1
      && path.nodes.every(item => item.prerequisites.every(parent => nodeIDs.includes(parent) && linkAllowed(item.id, parent))
        && (item.supports === null || (item.optional && nodeIDs.includes(item.supports)))
        && item.practiceTarget.target <= allowed[item.id].maxTarget && item.practiceTarget.perWeek <= Math.min(6, data.answers.sessionsPerWeek))
      && ![path.rationale, path.startReason, path.emphasis, ...path.nodes.map(item => item.why)].some(hasLink);
  });
}

const pathInstruction = 'Build one personalised training path from the supplied exercises only. Rules: 4 to 6 nodes; node id is the exercise id; the main chain follows the goal family in level order and includes the goal exercise; goalNode is the last step of the main chain, its highest level, which may be beyond the goal exercise; prerequisites only from each exercise\'s allowedPrerequisites or a lower level of the same family; at most one optional node, which no other node lists as a prerequisite, and whose supports names the node it helps; start must be ruleStart unless focus is learn or the band is unsure, and always one of allowedStarts; route lists node ids from start to goalNode where each node lists the previous one as a prerequisite; practiceTarget stays within maxTarget and at most the person\'s sessionsPerWeek. Write why (one sentence each) in the requested coaching style. For a node whose capability is practiceLog, say plainly that camera tracking is not trained for it yet. rationale: two sentences on why the route fits the answers. startReason: one sentence. emphasis: one sentence matching focus. No links, timelines, medical claims or promises of results. If repair lists errors from a previous attempt, fix exactly those.';

// ---------- coaching cue between baseline and retry ----------
const contract = z.strictObject({
  exerciseID: trackedID,
  version: boundedText(64),
  metric: z.enum(['lowering', 'repTime']),
  label: boundedText(40),
  target: z.number().min(0.3).max(10),
  tolerance: z.number().min(0.05).max(2)
});
const fact = z.strictObject({ id: boundedText(64), text: boundedText(300) });
const facts = z.array(fact).min(1).max(24).refine(list => unique(list.map(item => item.id)));
const evidence = data => z.array(z.enum(data.facts.map(item => item.id))).min(1).max(8).refine(unique);
// Numbers a text may state: those in the supplied facts, plus counting words up to five ("count to 2").
const numbersIn = text => (text.match(/\d+(?:\.\d+)?/g) ?? []).map(Number);
const grounded = (text, data) => {
  const allowed = new Set(data.facts.flatMap(item => numbersIn(item.text)));
  return numbersIn(text).every(value => allowed.has(value) || (Number.isInteger(value) && value >= 1 && value <= 5));
};

export const cueRequest = z.strictObject({
  generationID: boundedText(128),
  contract,
  baseline: z.strictObject({ validReps: z.number().int().min(3).max(20), median: z.number().min(0.1).max(30) }),
  coachingStyle: z.enum(['concise', 'encouraging', 'explanatory']).nullable().default(null),
  facts
});

export function cueOutputContract(data) {
  const meets = Math.abs(data.baseline.median - data.contract.target) <= data.contract.tolerance;
  return z.strictObject({
    generationID: z.enum([data.generationID]),
    action: z.enum(['cue_target', 'maintain_target', 'request_better_view']),
    text: boundedText(200),
    factIDs: evidence(data)
  }).refine(cue => (cue.action !== 'maintain_target' || meets) && (cue.action !== 'cue_target' || !meets)
    && grounded(cue.text, data) && !hasLink(cue.text));
}

const cueInstruction = 'Choose one coaching change between a baseline and a retry of the same movement. The target, tolerance and pass rule are fixed by the app and cannot change. Use maintain_target only when the baseline median is already within tolerance of the target; otherwise use cue_target with one short, concrete instruction about the timed phase; use request_better_view only when the facts say the view is poor. One sentence, at most 25 words, in the requested coaching style. State only numbers that appear in the facts. Cite the facts you used in factIDs; never write fact ids in the text. No praise of form the facts do not show, no medical claims.';

// ---------- explanation of the computed result ----------
export const explanationRequest = z.strictObject({
  generationID: boundedText(128),
  contract,
  outcome: z.strictObject({
    classification: z.enum(['closer', 'similar', 'further', 'unable']),
    retryMeets: z.boolean()
  }),
  coachingStyle: z.enum(['concise', 'encouraging', 'explanatory']).nullable().default(null),
  facts
});

export function explanationOutputContract(data) {
  return z.strictObject({
    generationID: z.enum([data.generationID]),
    text: boundedText(500),
    factIDs: evidence(data)
  }).refine(item => grounded(item.text, data) && !hasLink(item.text));
}

const explanationInstruction = 'Explain a result the app has already computed. Do not change, soften or upgrade it: the classification and whether the retry met the target are final. Two or three sentences in the requested coaching style. State only numbers that appear in the facts, and cite them in factIDs; never write fact ids in the text. If the result is unable, say why from the facts and what to do next time. No medical claims.';

export const pathTasks = {
  '/v1/path-proposal': { request: pathRequest, output: pathOutputContract, instruction: pathInstruction, maxOutputTokens: 4096 },
  '/v1/attempt-cue': { request: cueRequest, output: cueOutputContract, instruction: cueInstruction, maxOutputTokens: 1024 },
  '/v1/attempt-explanation': { request: explanationRequest, output: explanationOutputContract, instruction: explanationInstruction, maxOutputTokens: 1024 }
};
