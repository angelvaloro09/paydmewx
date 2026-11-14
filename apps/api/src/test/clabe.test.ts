import { describe, expect, it } from 'vitest';
import { computeClabeCheckDigit, isValidClabe } from '../lib/clabe.js';

describe('CLABE check-digit validator', () => {
  it('validates a known valid CLABE (012180015826225713)', () => {
    expect(isValidClabe('012180015826225713')).toBe(true);
    expect(computeClabeCheckDigit('01218001582622571')).toBe(3);
  });

  it('rejects a CLABE with an invalid check digit', () => {
    expect(isValidClabe('012180015826225714')).toBe(false);
    expect(isValidClabe('012180015826225710')).toBe(false);
  });

  it('rejects malformed CLABE strings', () => {
    expect(isValidClabe('')).toBe(false);
    expect(isValidClabe('01218001582622571')).toBe(false);
    expect(isValidClabe('0121800158262257130')).toBe(false);
    expect(isValidClabe('01218001582622571A')).toBe(false);
  });
});
