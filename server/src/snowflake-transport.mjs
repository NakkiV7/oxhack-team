import { z } from 'zod';
import { GatewayError } from './errors.mjs';

const configuration = z.object({
  SNOWFLAKE_ACCOUNT: z.string().max(200).regex(/^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$/),
  SNOWFLAKE_TOKEN: z.string().min(1).max(16384),
  SNOWFLAKE_TOKEN_TYPE: z.enum(['PROGRAMMATIC_ACCESS_TOKEN', 'KEYPAIR_JWT', 'OAUTH']).optional()
});
export const snowflakeHandle = z.string().regex(/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i);

export function createSnowflakeTransport({ env = process.env, fetchImpl = fetch, timeoutMs = 10000 } = {}) {
  return async ({ path, method, body, requestTimeoutMs = timeoutMs }) => {
    if (!configuration.safeParse(env).success || !Number.isInteger(requestTimeoutMs) || requestTimeoutMs < 1 || requestTimeoutMs > 60000) throw new GatewayError(503, 'missing_configuration', 'Snowflake account, server authorization and token type must be configured.');
    const encoded = body === undefined ? undefined : JSON.stringify(body);
    if (encoded && Buffer.byteLength(encoded) > 2_097_152) throw new GatewayError(422, 'invalid_public_artifact', 'The public benchmark exceeds the request limit.');
    const signal = AbortSignal.timeout(requestTimeoutMs);
    try {
      const response = await fetchImpl(`https://${env.SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/statements${path}`, {
        method, redirect: 'error', signal,
        headers: { Authorization: `Bearer ${env.SNOWFLAKE_TOKEN}`, 'X-Snowflake-Authorization-Token-Type': env.SNOWFLAKE_TOKEN_TYPE ?? 'PROGRAMMATIC_ACCESS_TOKEN', 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': 'SpottrGateway/1.0' },
        ...(encoded === undefined ? {} : { body: encoded })
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new GatewayError(response.status === 429 || response.status >= 500 ? 503 : 502, 'provider_unavailable', 'Snowflake is unavailable.');
      }
      const chunks = [];
      let size = 0;
      for await (const chunk of response.body ?? []) {
        size += chunk.length;
        if (size > 262144) throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
        chunks.push(chunk);
      }
      const result = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      return response.status === 202
        ? { pending: true, handle: snowflakeHandle.parse(result.statementHandle), body: result }
        : { pending: false, body: result };
    } catch (error) {
      if (signal.aborted) throw new GatewayError(504, 'provider_timeout', 'Snowflake timed out.');
      if (error instanceof GatewayError) throw error;
      throw new GatewayError(502, 'invalid_provider_response', 'The Snowflake response failed validation.');
    }
  };
}
