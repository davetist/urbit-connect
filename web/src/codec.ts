/** The same bounded, lossless JSON subset used by the ship and native SDK. */
export class JSONNumber {
  readonly raw: string;
  constructor(raw: string) { validateNumber(raw); this.raw = raw; }
  toString(): string { return this.raw; }
}
export type JSONValue = null | boolean | string | number | JSONNumber | JSONValue[] | { [key: string]: JSONValue };
export type JSONObject = { [key: string]: JSONValue };
export function isObject(value: unknown): value is JSONObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value) && !(value instanceof JSONNumber);
}
function validateString(value: string): void {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 0) throw new Error('U+0000 is outside the portable JSON subset');
    if (code >= 0xD800 && code <= 0xDBFF) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xDC00 && next <= 0xDFFF)) throw new Error('Unpaired Unicode surrogate');
    } else if (code >= 0xDC00 && code <= 0xDFFF) throw new Error('Unpaired Unicode surrogate');
  }
}
function validateNumber(raw: string): void {
  if (raw.length > 2048) throw new Error('Number spelling exceeds 2048 bytes');
  if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(raw)) throw new Error('Invalid JSON number');
  const [mantissa, exp = '0'] = raw.replace(/^-/, '').toLowerCase().split('e');
  const exponent = Number(exp), [whole, fraction = ''] = mantissa.split('.');
  if (!Number.isInteger(exponent) || Math.abs(exponent) > 1024 || fraction.length > 1024) throw new Error('Number exceeds precision bounds');
  const digits = (whole + fraction).replace(/^0+/, '');
  if (!digits) return;
  const integerCount = digits.length + exponent - fraction.length;
  if (integerCount > 16) throw new Error('Number exceeds the portable range');
  if (integerCount === 16) {
    const padded = digits.padEnd(16, '0'), integer = padded.slice(0, 16), remainder = padded.slice(16);
    if (integer > '9007199254740991' || (integer === '9007199254740991' && /[1-9]/.test(remainder))) throw new Error('Number exceeds the portable range');
  }
}
export function parseJSON(text: string, maxBytes = 262144, maxDepth = 16): JSONValue {
  if (!Number.isInteger(maxDepth) || maxDepth < 1 || maxDepth > 24) throw new Error('Invalid depth bound');
  validateString(text);
  if (new TextEncoder().encode(text).length > maxBytes) throw new Error('JSON exceeds its byte limit');
  let index = 0;
  const whitespace = () => { while (index < text.length && /[\x20\t\r\n]/.test(text[index])) index++; };
  const consume = (char: string) => { whitespace(); if (text[index] !== char) return false; index++; return true; };
  const string = (): string => {
    if (text[index] !== '"') throw new Error('Expected a quoted string');
    const start = index++;
    while (index < text.length) {
      const char = text[index++];
      if (char === '"') {
        const value: string = JSON.parse(text.slice(start, index)); validateString(value); return value;
      }
      if (char === '\\') index++;
      else if (char.charCodeAt(0) < 32) throw new Error('Unescaped control character');
    }
    throw new Error('Unterminated string');
  };
  const value = (depth: number): JSONValue => {
    whitespace(); const char = text[index];
    if (char === '"') return string();
    if (char === '{' || char === '[') {
      if (depth >= maxDepth) throw new Error(`JSON exceeds ${maxDepth} levels of nesting`);
      index++;
      if (char === '{') {
        const result: JSONObject = Object.create(null);
        if (consume('}')) return result;
        do {
          whitespace(); const key = string();
          if (Object.hasOwn(result, key)) throw new Error('Duplicate object key');
          if (!consume(':')) throw new Error('Expected colon');
          result[key] = value(depth + 1);
          if (consume('}')) return result;
          if (!consume(',')) throw new Error('Expected comma');
        } while (true);
      }
      const result: JSONValue[] = [];
      if (consume(']')) return result;
      do {
        result.push(value(depth + 1));
        if (consume(']')) return result;
        if (!consume(',')) throw new Error('Expected comma');
      } while (true);
    }
    for (const [token, result] of [['null', null], ['true', true], ['false', false]] as const) {
      if (text.startsWith(token, index)) { index += token.length; return result; }
    }
    const start = index;
    while (index < text.length && !/[\x20\t\r\n,\]}]/.test(text[index])) index++;
    return new JSONNumber(text.slice(start, index));
  };
  const result = value(0); whitespace();
  if (index !== text.length) throw new Error('Trailing JSON content');
  return result;
}
export function stringifyJSON(value: unknown, pretty = false, maxDepth = 16): string {
  if (!Number.isInteger(maxDepth) || maxDepth < 1 || maxDepth > 24) throw new Error('Invalid depth bound');
  const encode = (value: unknown, depth: number): string => {
    if (depth > maxDepth || (depth === maxDepth && value !== null && typeof value === 'object' && !(value instanceof JSONNumber))) throw new Error(`JSON exceeds ${maxDepth} levels of nesting`);
    if (value instanceof JSONNumber) return value.raw;
    if (value === null || typeof value === 'boolean') return String(value);
    if (typeof value === 'number') { validateNumber(String(value)); return String(value); }
    if (typeof value === 'string') { validateString(value); return JSON.stringify(value); }
    if (typeof value !== 'object') throw new Error('Unsupported JSON value');
    const pad = pretty ? '  '.repeat(depth + 1) : '', end = pretty ? '\n' + '  '.repeat(depth) : '';
    const join = (items: string[], open: string, close: string) => items.length ? open + (pretty ? '\n' : '') + pad + items.join(pretty ? ',\n' + pad : ',') + end + close : open + close;
    if (Array.isArray(value)) return join(value.map(v => encode(v, depth + 1)), '[', ']');
    return join(Object.keys(value).sort().map(key => encode(key, depth + 1) + (pretty ? ': ' : ':') + encode((value as Record<string, unknown>)[key], depth + 1)), '{', '}');
  };
  return encode(value, 0);
}
