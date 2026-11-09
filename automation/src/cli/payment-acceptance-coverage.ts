export function hasExactPaymentAcceptanceCoverage(expectedKeys: string[], actualKeys: string[]): boolean {
  if (expectedKeys.length === 0 || expectedKeys.length !== actualKeys.length) return false;
  if (new Set(expectedKeys).size !== expectedKeys.length || new Set(actualKeys).size !== actualKeys.length) return false;
  const expected = [...expectedKeys].sort();
  const actual = [...actualKeys].sort();
  return expected.every((key, index) => key === actual[index]);
}
