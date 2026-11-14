import { buildApp } from './app.js';
import { config } from './config.js';

async function start(): Promise<void> {
  const app = await buildApp();
  try {
    await app.listen({ port: config.PORT, host: config.HOST });
    console.log(`PaydMewx API listening on http://localhost:${config.PORT}`);
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();
