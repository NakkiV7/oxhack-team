import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { GatewayError } from './errors.mjs';

const configuration = z.object({
  SNOWFLAKE_ACCOUNT: z.string().max(200).regex(/^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$/),
  SNOWFLAKE_TOKEN: z.string().min(1).max(16384),
  SNOWFLAKE_TOKEN_TYPE: z.enum(['PROGRAMMATIC_ACCESS_TOKEN', 'KEYPAIR_JWT', 'OAUTH']).optional()
});
const statementHandle = z.string().regex(/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i);
const ready = z.object({ data: z.array(z.tuple([z.string().min(1).max(128)])).length(1) });
const pending = z.object({ statementHandle });

async function readBody(response) {
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body ?? []) {
    size += chunk.length;
    if (size > 262144) throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export function createSnowflakeAdapter({ env = process.env, fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  const request = async ({ path, method }) => {
    if (!configuration.safeParse(env).success || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000) throw new GatewayError(503, 'missing_configuration', 'Snowflake account, server authorization and token type must be configured.');
    const signal = AbortSignal.timeout(timeoutMs);
    try {
      const response = await fetchImpl(`https://${env.SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/statements${path}`, {
        method,
        redirect: 'error',
        signal,
        headers: { Authorization: `Bearer ${env.SNOWFLAKE_TOKEN}`, 'X-Snowflake-Authorization-Token-Type': env.SNOWFLAKE_TOKEN_TYPE ?? 'PROGRAMMATIC_ACCESS_TOKEN', 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': 'SpottrGateway/1.0' },
        ...(method === 'POST' ? { body: JSON.stringify({ statement: 'SELECT CURRENT_VERSION()', timeout: 10, ...(env.SNOWFLAKE_WAREHOUSE ? { warehouse: env.SNOWFLAKE_WAREHOUSE } : {}) }) } : {})
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new GatewayError(response.status === 429 || response.status >= 500 ? 503 : 502, 'provider_unavailable', 'Snowflake is unavailable.');
      }
      const body = await readBody(response);
      if (response.status === 202) return { status: 'pending', statementHandle: pending.parse(body).statementHandle };
      return { status: 'ready', version: ready.parse(body).data[0][0] };
    } catch (error) {
      if (signal.aborted) throw new GatewayError(504, 'provider_timeout', 'Snowflake timed out.');
      if (error instanceof GatewayError) throw error;
      throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
    }
  };
  return {
    check: () => request({ path: `?requestId=${randomUUID()}`, method: 'POST' }),
    status: async handle => {
      if (!statementHandle.safeParse(handle).success) throw new GatewayError(422, 'invalid_request', 'A valid Snowflake statement handle is required.');
      return request({ path: `/${handle}`, method: 'GET' });
    }
  };
}
