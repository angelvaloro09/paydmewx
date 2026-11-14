import { describe, expect, it } from 'vitest';
import { loadConfig } from '../config.js';

describe('config', () => {
  it('rejects insecure JWT_SECRET in production', () => {
    expect(() => loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'change-me' })).toThrow(
      /JWT_SECRET/
    );
    expect(() => loadConfig({ NODE_ENV: 'production', JWT_SECRET: undefined })).toThrow(
      /JWT_SECRET/
    );
  });

  it('accepts a strong JWT_SECRET in production', () => {
    const cfg = loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'x'.repeat(40) });
    expect(cfg.JWT_SECRET).toHaveLength(40);
  });
});
