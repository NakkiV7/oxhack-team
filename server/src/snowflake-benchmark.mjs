import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { GatewayError } from './errors.mjs';

const header = 'subject,origin,horizon,target_window_start,target_window_end,target,frozen,adaptive,persistence,prior_matured_updates,updates_after_prediction,cold_start';
const columns = header.split(',');
const models = ['frozen', 'adaptive', 'persistence'];
const invalid = () => new GatewayError(422, 'invalid_public_artifact', 'The pinned public benchmark artifact failed validation.');
export const canonical = value => JSON.stringify(sort(value));
const sort = value => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const sha = value => createHash('sha256').update(value).digest('hex');
const integer = value => Number.isSafeInteger(Number(value)) && /^\d+$/.test(String(value));
const finite = value => /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value) && Number.isFinite(Number(value));

export function parsePredictionCSV(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > 1_048_576 || text.includes('"')) throw invalid();
  const lines = text.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
  if (lines.shift() !== header || !lines.length || lines.length > 10000) throw invalid();
  const seen = new Set();
  const previous = new Map();
  return lines.map(line => {
    const cells = line.split(',');
    if (cells.length !== columns.length) throw invalid();
    const row = Object.fromEntries(columns.map((key, index) => [key, cells[index]]));
    for (const key of ['subject', 'origin', 'horizon', 'target_window_start', 'target_window_end', 'prior_matured_updates', 'updates_after_prediction']) if (!integer(row[key])) throw invalid();
    const subject = Number(row.subject), horizon = Number(row.horizon), origin = Number(row.origin);
    if (![108, 109].includes(subject) || ![10, 30].includes(horizon) || origin % 5 !== 0
      || Number(row.target_window_start) !== origin + horizon - 5 || Number(row.target_window_end) !== origin + horizon) throw invalid();
    for (const key of models) if (!finite(row[key])) throw invalid();
    if (row.target !== '' && (!finite(row.target) || Number(row.target) <= 0)) throw invalid();
    if (!['True', 'False'].includes(row.cold_start) || (row.cold_start === 'True') !== (Number(row.prior_matured_updates) < 10)) throw invalid();
    const group = `${subject}:${horizon}`, key = `${group}:${origin}`;
    if (seen.has(key) || origin <= (previous.get(group) ?? -1)) throw invalid();
    seen.add(key); previous.set(group, origin);
    return { ...row, target: row.target === '' ? null : row.target };
  });
}

function statistics(rows, model) {
  if (!rows.length) return { mae: null, rmse: null, bias: null };
  const errors = rows.map(row => Number(row[model]) - Number(row.target));
  return {
    mae: errors.reduce((total, value) => total + Math.abs(value), 0) / rows.length,
    rmse: Math.sqrt(errors.reduce((total, value) => total + value ** 2, 0) / rows.length),
    bias: errors.reduce((total, value) => total + value, 0) / rows.length
  };
}

function evaluation(predictions, coverage, report) {
  if (!Array.isArray(coverage) || coverage.length !== 4) throw invalid();
  const metrics = [];
  for (const subject of [108, 109]) for (const horizon of [10, 30]) {
    const counts = coverage.filter(row => row.subject === subject && row.horizon === horizon);
    if (counts.length !== 1) throw invalid();
    const count = counts[0];
    for (const key of ['planned_origins', 'hr_input_eligible', 'target_observed', 'hr_scored', 'delivered_forecasts', 'scored_forecasts']) if (!integer(count[key])) throw invalid();
    const delivered = predictions.filter(row => Number(row.subject) === subject && Number(row.horizon) === horizon);
    const scored = delivered.filter(row => row.target !== null);
    if (count.planned_origins < delivered.length || delivered.length !== count.hr_input_eligible
      || delivered.length !== count.delivered_forecasts || scored.length !== count.hr_scored
      || scored.length !== count.scored_forecasts || count.target_observed < scored.length
      || count.target_observed > count.planned_origins) throw invalid();
    for (const model of models) {
      const values = statistics(scored, model);
      const recorded = report.test_results?.[horizon]?.selected_primary_same_origins?.[model]?.per_participant?.[subject];
      if (scored.length && (!recorded || recorded.count !== scored.length || ['mae', 'rmse', 'bias'].some(key => Math.abs(recorded[key] - values[key]) > 1e-9))) throw invalid();
      if (!scored.length && recorded) throw invalid();
      metrics.push({ subject, horizon, model, planned: count.planned_origins, delivered: delivered.length,
        targetObserved: count.target_observed, scored: scored.length, ...values, contributingParticipants: scored.length ? 1 : 0 });
    }
  }
  for (const horizon of [10, 30]) for (const model of models) {
    const own = metrics.filter(row => row.subject !== null && row.horizon === horizon && row.model === model);
    const scored = own.filter(row => row.scored > 0);
    const average = key => scored.length ? scored.reduce((sum, row) => sum + row[key], 0) / scored.length : null;
    metrics.push({ subject: null, horizon, model, planned: own.reduce((sum, row) => sum + row.planned, 0),
      delivered: own.reduce((sum, row) => sum + row.delivered, 0), targetObserved: own.reduce((sum, row) => sum + row.targetObserved, 0),
      scored: own.reduce((sum, row) => sum + row.scored, 0), mae: average('mae'), rmse: average('rmse'), bias: average('bias'), contributingParticipants: scored.length });
  }
  return metrics;
}

async function boundedFile(path) {
  const chunks = [];
  let size = 0;
  for await (const chunk of createReadStream(path)) {
    size += chunk.length;
    if (size > 1_048_576) throw invalid();
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export async function loadPublicBenchmark({ root = fileURLToPath(new URL('../../research/hr_forecast/', import.meta.url)), manifest } = {}) {
  try {
    const pinned = manifest ?? JSON.parse(await readFile(new URL('../../integrations/snowflake/pamap2-forecast-v1.manifest.json', import.meta.url), 'utf8'));
    if (pinned.version !== 'spottr-pamap-forecast-v1' || pinned.dataset !== 'PAMAP2' || pinned.license !== 'CC BY 4.0') throw invalid();
    const files = {};
    let size = 0;
    for (const [name, digest] of Object.entries(pinned.files)) {
      if (!/^(?:results\/(?:run-source\/)?)?[a-z-]+\.(?:json|csv|py|sha256)$/.test(name) || !/^[a-f0-9]{64}$/.test(digest)) throw invalid();
      const bytes = await boundedFile(resolve(root, name));
      size += bytes.length;
      if (size > 2_097_152 || sha(bytes) !== digest) throw invalid();
      files[name] = bytes.toString('utf8');
    }
    const json = name => JSON.parse(files[name]);
    const protocol = json('protocol.json'), provenance = json('provenance.json'), report = json('results/report.json');
    if (sha(files['protocol.json']) !== report.protocol_sha256 || sha(files['results/selection.json']) !== report.selection_sha256_before_test_scoring
      || sha(files['provenance.json']) !== report.provenance_sha256 || provenance.data_zip_sha256.length !== 64
      || ![10, 30].every(horizon => json('results/selection.json').horizons[horizon].selected === 'hr-ridge-0.1')
      || canonical(protocol.dataset.test) !== '[108,109]') throw invalid();
    for (const [name, digest] of Object.entries(report.code_sha256)) if (sha(files[`results/run-source/${name}`]) !== digest) throw invalid();
    const predictions = parsePredictionCSV(files['results/test-predictions.csv']);
    const coverage = json('results/coverage-summary.json');
    const metrics = evaluation(predictions, coverage, report);
    const payload = { lineage: { ...pinned, attribution: json('license-attribution.json').attribution, datasetArchiveSha256: provenance.data_zip_sha256,
      protocolSha256: report.protocol_sha256, selected: { 10: 'hr-ridge-0.1', 30: 'hr-ridge-0.1' } },
    modelsJSON: files['results/models.json'], protocolJSON: files['protocol.json'], selectionJSON: files['results/selection.json'], predictions, coverage };
    const payloadJSON = canonical(payload);
    if (Buffer.byteLength(payloadJSON) > 1_900_000) throw invalid();
    return { runID: sha(canonical(pinned)), payloadSha256: sha(payloadJSON), payloadJSON, payload, sourceRows: predictions.length, metrics };
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    throw invalid();
  }
}
