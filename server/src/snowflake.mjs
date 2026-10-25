import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { GatewayError } from './errors.mjs';
import { createSnowflakeTransport, snowflakeHandle } from './snowflake-transport.mjs';

const ready = z.object({ data: z.array(z.tuple([z.string().min(1).max(128)])).length(1) });

export function createSnowflakeAdapter({ env = process.env, fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  const transport = createSnowflakeTransport({ env, fetchImpl, timeoutMs });
  const request = async ({ path, method }) => {
    try {
      const result = await transport({ path, method,
        ...(method === 'POST' ? { body: { statement: 'SELECT CURRENT_VERSION()', timeout: 10, ...(env.SNOWFLAKE_WAREHOUSE ? { warehouse: env.SNOWFLAKE_WAREHOUSE } : {}) } } : {}) });
      if (result.pending) return { status: 'pending', statementHandle: result.handle };
      return { status: 'ready', version: ready.parse(result.body).data[0][0] };
    } catch (error) {
      if (error instanceof GatewayError) throw error;
      throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
    }
  };
  return {
    check: () => request({ path: `?requestId=${randomUUID()}`, method: 'POST' }),
    status: async handle => {
      if (!snowflakeHandle.safeParse(handle).success) throw new GatewayError(422, 'invalid_request', 'A valid Snowflake statement handle is required.');
      return request({ path: `/${handle}`, method: 'GET' });
    }
  };
}
