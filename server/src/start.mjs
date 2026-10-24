import { createGateway } from './gateway.mjs';

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '127.0.0.1';
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error('PORT must be an integer from 0 to 65535.');
  process.exit(1);
}
const server = createGateway();
server.on('error', () => { console.error('Gateway could not listen; check HOST and PORT.'); process.exitCode = 1; });
server.listen(port, host, () => {
  console.log(`Spottr gateway listening on http://${host}:${server.address().port}`);
});
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { server.close(); server.closeIdleConnections(); });
