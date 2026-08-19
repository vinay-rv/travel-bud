/**
 * Reads a `.env` file into `process.env`.
 *
 * Deliberately not a dependency: this is twenty lines, and the alternative is
 * pulling a package into the trust boundary of a service that handles
 * passwords.
 *
 * Two rules matter:
 *
 * - **Missing files are fine.** In production there is no `.env` at all — the
 *   platform injects real environment variables — so absence is normal, not an
 *   error.
 * - **Never overwrite what is already set.** A real environment variable beats
 *   a file every time, which is what lets tests point at the test database and
 *   lets a deployment override anything.
 */
import { readFileSync } from 'node:fs';

export function loadEnvFile(location: URL): void {
  let contents: string;
  try {
    contents = readFileSync(location, 'utf8');
  } catch {
    return;
  }

  for (const line of contents.split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    const key = match?.[1];
    const rawValue = match?.[2];
    if (key === undefined || rawValue === undefined) continue;
    if (process.env[key] !== undefined) continue;
    process.env[key] = rawValue.replace(/^["']|["']$/g, '');
  }
}
