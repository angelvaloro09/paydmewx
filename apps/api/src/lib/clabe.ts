const CLABE_WEIGHTS = [3, 7, 1] as const;

/**
 * Validates an 18-digit Mexican CLABE (Clave Bancaria Estandarizada)
 * using the standard modulo-10 check digit algorithm with weights 3, 7, 1.
 */
export function isValidClabe(clabe: string): boolean {
  if (typeof clabe !== 'string' || !/^\d{18}$/.test(clabe)) {
    return false;
  }

  let sum = 0;
  for (let i = 0; i < 17; i++) {
    const digit = Number(clabe[i]);
    const weight = CLABE_WEIGHTS[i % 3]!;
    sum += (digit * weight) % 10;
  }

  const expectedCheckDigit = (10 - (sum % 10)) % 10;
  const actualCheckDigit = Number(clabe[17]);

  return expectedCheckDigit === actualCheckDigit;
}

export const validateClabe = isValidClabe;


export function computeClabeCheckDigit(first17Digits: string): number {
  if (!/^\d{17}$/.test(first17Digits)) {
    throw new Error('Expected 17 digits');
  }
  let sum = 0;
  for (let i = 0; i < 17; i++) {
    const digit = Number(first17Digits[i]);
    const weight = CLABE_WEIGHTS[i % 3]!;
    sum += (digit * weight) % 10;
  }
  return (10 - (sum % 10)) % 10;
}
