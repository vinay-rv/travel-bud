import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // These talk to a real Postgres. Running files in parallel against one
    // database would have them truncating each other's rows mid-test.
    fileParallelism: false,
    testTimeout: 30_000,
  },
});
