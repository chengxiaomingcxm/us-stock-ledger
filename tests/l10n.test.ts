import { it, expect } from 'vitest';
import { readFileSync } from 'node:fs';

// A duplicate key in the L10n English dictionary traps at runtime
// ("Dictionary literal contains duplicate keys"), killing the app the first
// time an English string is rendered. Chinese never touches the dictionary
// (L10n.tr returns early), so the bug only appears after switching languages.
it('L10n English dictionary has no duplicate keys (Swift traps on duplicates)', () => {
  const source = readFileSync('ios/App/App/StockLedger/L10n.swift', 'utf8');
  const start = source.indexOf('static let en: [String: String] = [');
  expect(start).toBeGreaterThan(-1);
  const keys = [...source.slice(start).matchAll(/^\s*"((?:[^"\\]|\\.)*)"\s*:/gm)].map((m) => m[1]);
  // Guard against the parser silently matching nothing.
  expect(keys.length).toBeGreaterThan(150);
  const seen = new Set<string>();
  const duplicates: string[] = [];
  for (const key of keys) {
    if (seen.has(key)) duplicates.push(key);
    seen.add(key);
  }
  expect(duplicates).toEqual([]);
});
