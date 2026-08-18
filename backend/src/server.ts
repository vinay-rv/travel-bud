/**
 * Process entry point. Everything interesting is in `buildApp`; this only
 * decides how the process talks to the outside world.
 */
import { buildApp } from './app.js';
import { env } from './lib/env.js';
import { createMailer } from './lib/mailer.js';

const app = await buildApp({ mailer: createMailer(), logger: true });

// 0.0.0.0 so the app works from a phone or emulator on the same network, not
// just from this machine.
await app.listen({ port: env.PORT, host: '0.0.0.0' });
