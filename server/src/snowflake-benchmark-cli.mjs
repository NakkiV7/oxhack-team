import { loadPublicBenchmark } from './snowflake-benchmark.mjs';
import { runSnowflakeBenchmark, snowflakeBenchmarkConfiguration } from './snowflake-benchmark-client.mjs';
import { GatewayError } from './errors.mjs';

try {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--check-configuration') {
    const configuration = snowflakeBenchmarkConfiguration();
    console.log(JSON.stringify(configuration));
    process.exitCode = configuration.ready ? 0 : 1;
  } else {
    let root, allowLivePublicData = false;
    while (args.length) {
      const argument = args.shift();
      if (argument === '--allow-live-public-data' && !allowLivePublicData) { allowLivePublicData = true; continue; }
      if (argument === '--artifacts' && root === undefined && args.length && !args[0].startsWith('--')) { root = args.shift(); continue; }
      throw new GatewayError(422, 'invalid_request', 'Use --check-configuration alone, or --artifacts DIR and optional --allow-live-public-data.');
    }
    const plan = await loadPublicBenchmark({ root });
    console.log(JSON.stringify(await runSnowflakeBenchmark({ plan, allowLivePublicData })));
  }
} catch (error) {
  const failure = error instanceof GatewayError ? error : new GatewayError(502, 'benchmark_failed', 'The public benchmark workflow failed.');
  console.error(JSON.stringify({ error: { code: failure.code, message: failure.message } }));
  process.exitCode = 1;
}
