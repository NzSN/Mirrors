/** Application boundary: convert actual native ITF/JSON observations to port values. */
export function fromWire(value) {
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new Error('native observation integer exceeds safe JSON range');
    return BigInt(value);
  }
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(fromWire);
  const keys = Object.keys(value);
  if (keys.length === 1) {
    if (keys[0] === '#bigint') return BigInt(value['#bigint']);
    if (['#set', '#tup', '#map'].includes(keys[0])) return value[keys[0]].map(fromWire);
  }
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, fromWire(item)]));
}
