import { createSnowflakeAdapter } from './snowflake.mjs';
import { GatewayError } from './errors.mjs';

try {
  const adapter = createSnowflakeAdapter();
  const handle = process.argv[2];
  console.log(JSON.stringify(await (handle ? adapter.status(handle) : adapter.check())));
} catch (error) {
  const failure = error instanceof GatewayError ? error : new GatewayError(502, 'provider_unavailable', 'Snowflake is unavailable.');
  console.error(JSON.stringify({ error: { code: failure.code, message: failure.message } }));
  process.exitCode = 1;
}
