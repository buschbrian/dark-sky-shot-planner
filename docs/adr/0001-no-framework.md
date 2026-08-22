# ADR-0001: No framework — plain DOM with TypeScript modules

**Status:** accepted · **Date:** 2026-08-22

## Decision

The client is plain TypeScript modules manipulating the DOM directly, built
with Vite. No React, Vue, Svelte, or other UI framework.

## Alternatives considered

- **React** — the default reflex for interactive apps. Rejected: the app has
  exactly one dynamic panel ("The Answer"), one date input, and a handful of
  checkboxes. React would add ~45 kB gzipped and a build-time mental model
  (components/hooks/reconciliation) that buys nothing here.
- **Lit / Preact / Solid** — smaller runtime cost but still an abstraction
  layer over what is fundamentally "update some text nodes."

## Reasoning

The product is text-first; state is a single object derived from URL +
inputs, and re-render is cheap. Fewer dependencies also means a smaller
bundle on throttled 3G — the real user's context — and fewer supply-chain
surfaces in a project whose value proposition includes being trustworthy.

## Consequences

We own our re-render discipline. If the UI ever grows genuinely complex
views, this decision should be revisited rather than defended by inertia.
