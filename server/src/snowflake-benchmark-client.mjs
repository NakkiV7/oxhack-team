import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { z } from 'zod';
import { GatewayError } from './errors.mjs';
import { createSnowflakeTransport, snowflakeConfiguration } from './snowflake-transport.mjs';

export const BENCHMARK_SQL = Object.freeze({
  lookup: `SELECT COUNT(*)::VARCHAR, COALESCE(MIN(PAYLOAD_SHA256), '')
FROM SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS WHERE RUN_ID = ?`,
  insert: `MERGE INTO SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS T
USING (SELECT ?::VARCHAR RUN_ID, ?::VARCHAR PAYLOAD_SHA256, PARSE_JSON(?) PAYLOAD) S
ON T.RUN_ID = S.RUN_ID
WHEN NOT MATCHED THEN INSERT (RUN_ID, PAYLOAD_SHA256, PAYLOAD)
VALUES (S.RUN_ID, S.PAYLOAD_SHA256, S.PAYLOAD)`,
  evaluate: `WITH B AS (SELECT PAYLOAD FROM SPOTTR_PUBLIC_PAMAP_FORECAST_RUNS WHERE RUN_ID = ?),
C AS (SELECT V.VALUE:subject::INTEGER SUBJECT, V.VALUE:horizon::INTEGER HORIZON,
 V.VALUE:planned_origins::INTEGER PLANNED, V.VALUE:target_observed::INTEGER TARGET_OBSERVED
 FROM B, LATERAL FLATTEN(INPUT => B.PAYLOAD:coverage) V),
P AS (SELECT V.VALUE:subject::INTEGER SUBJECT, V.VALUE:horizon::INTEGER HORIZON,
 TRY_TO_DOUBLE(V.VALUE:target::VARCHAR) TARGET,
 V.VALUE:frozen::VARCHAR FROZEN, V.VALUE:adaptive::VARCHAR ADAPTIVE, V.VALUE:persistence::VARCHAR PERSISTENCE
 FROM B, LATERAL FLATTEN(INPUT => B.PAYLOAD:predictions) V),
M AS (SELECT COLUMN1::VARCHAR MODEL FROM VALUES ('frozen'), ('adaptive'), ('persistence')),
E AS (SELECT P.SUBJECT, P.HORIZON, M.MODEL, P.TARGET,
 CASE M.MODEL WHEN 'frozen' THEN TRY_TO_DOUBLE(P.FROZEN) WHEN 'adaptive' THEN TRY_TO_DOUBLE(P.ADAPTIVE)
 ELSE TRY_TO_DOUBLE(P.PERSISTENCE) END PREDICTION FROM P CROSS JOIN M),
S AS (SELECT C.SUBJECT, C.HORIZON, M.MODEL, C.PLANNED, C.TARGET_OBSERVED,
 COUNT(E.SUBJECT) DELIVERED, COUNT(E.TARGET) SCORED,
 AVG(ABS(E.PREDICTION-E.TARGET)) MAE, SQRT(AVG(POWER(E.PREDICTION-E.TARGET,2))) RMSE,
 AVG(E.PREDICTION-E.TARGET) BIAS, IFF(COUNT(E.TARGET)>0,1,0) CONTRIBUTING
 FROM C CROSS JOIN M LEFT JOIN E ON E.SUBJECT=C.SUBJECT AND E.HORIZON=C.HORIZON AND E.MODEL=M.MODEL
 GROUP BY C.SUBJECT, C.HORIZON, M.MODEL, C.PLANNED, C.TARGET_OBSERVED),
U AS (SELECT * FROM S UNION ALL SELECT NULL, HORIZON, MODEL, SUM(PLANNED), SUM(TARGET_OBSERVED),
 SUM(DELIVERED), SUM(SCORED), AVG(MAE), AVG(RMSE), AVG(BIAS), SUM(CONTRIBUTING) FROM S GROUP BY HORIZON, MODEL)
SELECT TO_JSON(ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL('subject',SUBJECT,'horizon',HORIZON,'model',MODEL,
 'planned',PLANNED,'targetObserved',TARGET_OBSERVED,'delivered',DELIVERED,'scored',SCORED,
 'mae',MAE,'rmse',RMSE,'bias',BIAS,'contributingParticipants',CONTRIBUTING))) FROM U`
});

const identifier = z.string().min(1).max(128).regex(/^[a-zA-Z_][a-zA-Z0-9_$]*$/);
const configuration = snowflakeConfiguration.extend({
  SNOWFLAKE_DATABASE: identifier.refine(name => !name.toUpperCase().startsWith('USER$')),
  SNOWFLAKE_SCHEMA: identifier, SNOWFLAKE_WAREHOUSE: identifier, SNOWFLAKE_ROLE: identifier.optional()
});

export function snowflakeBenchmarkConfiguration({ env = process.env } = {}) {
  const missing = [], invalid = [];
  for (const [key, schema] of Object.entries(configuration.shape)) {
    if (!schema.safeParse(env[key]).success) (env[key] === undefined || env[key] === '' ? missing : invalid).push(key);
  }
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0' || process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0') invalid.push('NODE_TLS_REJECT_UNAUTHORIZED');
  return { mode: 'configuration', ready: missing.length === 0 && invalid.length === 0, missing, invalid };
}
const timeout = () => new GatewayError(504, 'provider_timeout', 'Snowflake exceeded the bounded benchmark deadline.');
const conflict = () => new GatewayError(409, 'immutable_run_conflict', 'The public benchmark run conflicts with an existing or duplicate run.');
const textBinding = value => ({ type: 'TEXT', value });

function lookup(body, expected) {
  const result = z.object({ data: z.array(z.tuple([z.string().regex(/^\d+$/), z.string().max(64)])).length(1) }).safeParse(body);
  if (!result.success) throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
  const [count, digest] = result.data.data[0];
  if (Number(count) > 1 || (Number(count) === 1 && digest !== expected)) throw conflict();
  return Number(count);
}

function reconcile(body, expected) {
  try {
    const encoded = z.object({ data: z.array(z.tuple([z.string().max(65536)])).length(1) }).parse(body).data[0][0];
    const rows = JSON.parse(encoded);
    if (!Array.isArray(rows) || rows.length !== expected.length) throw Error();
    return expected.map(reference => {
      const own = rows.filter(row => row.subject === reference.subject && row.horizon === reference.horizon && row.model === reference.model);
      if (own.length !== 1 || Object.keys(own[0]).length !== Object.keys(reference).length) throw Error();
      for (const [key, value] of Object.entries(reference)) {
        if (typeof value === 'number') {
          if (typeof own[0][key] !== 'number' || !Number.isFinite(own[0][key]) || Math.abs(own[0][key] - value) > 1e-8) throw Error();
        } else if (own[0][key] !== value) throw Error();
      }
      return own[0];
    });
  } catch {
    throw new GatewayError(502, 'evaluation_mismatch', 'Snowflake evaluation did not reconcile with the pinned public benchmark.');
  }
}

export async function runSnowflakeBenchmark({ plan, allowLivePublicData = false, env = process.env, fetchImpl = fetch,
  maxPolls = 10, pollMs = 1000, totalTimeoutMs = 90000, waitImpl = sleep, now = Date.now } = {}) {
  const summary = { runID: plan.runID, payloadSha256: plan.payloadSha256, sourceRows: plan.sourceRows, metrics: plan.metrics };
  if (allowLivePublicData !== true) return { mode: 'dry-run', ...summary };
  if (!snowflakeBenchmarkConfiguration({ env }).ready) throw new GatewayError(503, 'missing_configuration', 'Existing Snowflake authorization, database, schema, warehouse and strict TLS must be configured.');
  if (!Number.isInteger(maxPolls) || maxPolls < 1 || maxPolls > 10 || !Number.isInteger(pollMs) || pollMs < 1 || pollMs > 1000
    || !Number.isInteger(totalTimeoutMs) || totalTimeoutMs < 1 || totalTimeoutMs > 90000) throw new GatewayError(422, 'invalid_request', 'The benchmark deadline configuration is invalid.');
  const transport = createSnowflakeTransport({ env, fetchImpl });
  const deadline = now() + totalTimeoutMs;
  let polls = 0;
  const execute = async (statement, values) => {
    let handle;
    const request = options => {
      const requestTimeoutMs = Math.floor(Math.min(10000, deadline - now() - 5000));
      if (requestTimeoutMs < 1) throw timeout();
      return transport({ ...options, requestTimeoutMs });
    };
    try {
      let result = await request({ path: `?requestId=${randomUUID()}&async=true`, method: 'POST', body: {
        statement, bindings: Object.fromEntries(values.map((value, index) => [String(index + 1), textBinding(value)])), timeout: 60,
        database: env.SNOWFLAKE_DATABASE, schema: env.SNOWFLAKE_SCHEMA, warehouse: env.SNOWFLAKE_WAREHOUSE,
        ...(env.SNOWFLAKE_ROLE ? { role: env.SNOWFLAKE_ROLE } : {})
      } });
      if (result.pending) handle = result.handle;
      while (result.pending) {
        if (polls >= maxPolls || now() + pollMs >= deadline - 5000) throw timeout();
        polls++;
        await waitImpl(pollMs);
        result = await request({ path: `/${handle}`, method: 'GET' });
        if (result.pending && result.handle !== handle) throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
      }
      handle = undefined;
      return result.body;
    } catch (error) {
      if (handle) {
        try {
          const cancelled = await transport({ path: `/${handle}/cancel`, method: 'POST', requestTimeoutMs: 5000 });
          if (cancelled.pending) throw Error();
        } catch { throw new GatewayError(502, 'cancel_unconfirmed', 'Snowflake statement cancellation could not be confirmed.'); }
      }
      throw error;
    }
  };
  const existing = lookup(await execute(BENCHMARK_SQL.lookup, [plan.runID]), plan.payloadSha256);
  if (!existing) {
    await execute(BENCHMARK_SQL.insert, [plan.runID, plan.payloadSha256, plan.payloadJSON]);
    if (lookup(await execute(BENCHMARK_SQL.lookup, [plan.runID]), plan.payloadSha256) !== 1) throw conflict();
  }
  const metrics = reconcile(await execute(BENCHMARK_SQL.evaluate, [plan.runID]), plan.metrics);
  return { mode: 'live', ...summary, replayed: existing === 1, metrics };
}
