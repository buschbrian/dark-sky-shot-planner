/**
 * Resolve a published artifact path against the site's base path.
 *
 * On GitHub Pages the site lives under "/<repo>/", so "/config.json" would
 * 404 against the account root. Vite exposes the configured base as
 * import.meta.env.BASE_URL ("/" in dev, "/dark-sky-shot-planner/" in the
 * Pages build); every fetch of a pipeline artifact goes through here.
 */
export function dataUrl(path: string, base: string = import.meta.env.BASE_URL): string {
  const prefix = base.endsWith("/") ? base : `${base}/`;
  return prefix + path.replace(/^\/+/, "");
}
