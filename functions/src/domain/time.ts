// Server time helpers. All "days" are UTC calendar days "yyyy-MM-dd" (spec §7, backend-spec).

export const HOUR_MS = 60 * 60 * 1000;
export const DAY_MS = 24 * HOUR_MS;

export function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

export function addDays(day: string, n: number): string {
  const ms = Date.parse(day + "T00:00:00.000Z");
  if (Number.isNaN(ms)) throw new RangeError(`bad day ${day}`);
  return utcDay(ms + n * DAY_MS);
}
