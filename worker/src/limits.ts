/** Kept out of index.ts: workerd treats every export of the main module as an entrypoint. */

/** Must match `ratelimits[].simple.period` in wrangler.jsonc. */
export const RATE_LIMIT_PERIOD_SECONDS = 60;
export const MAX_UPSTREAM_FETCHES = 20;
