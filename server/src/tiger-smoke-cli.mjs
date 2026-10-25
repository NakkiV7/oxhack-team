import { tigerSmokeCommand } from './tiger-smoke.mjs';

const { exitCode, ...output } = await tigerSmokeCommand();
process.exitCode = exitCode;
if (exitCode) console.error(JSON.stringify(output));
else console.log(JSON.stringify(output));
