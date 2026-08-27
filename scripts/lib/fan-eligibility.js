'use strict';

// =============================================================================
// fan-eligibility.js — pure fan/serialize eligibility predicate (issue #8)
// -----------------------------------------------------------------------------
// KEEP-IN-SYNC WARNING (sub-build 3 will enforce this):
//
//   campaign.js runs inside the Workflow sandbox, which has NO require/import,
//   NO fs, and NO module system. This predicate therefore CANNOT be imported
//   there — a byte-for-byte copy of fanEligibility/normalizePath/pathsConflict
//   must be INLINED into campaign.js in a later sub-build, wrapped in a
//   clearly-marked block, e.g.:
//
//       // >>> BEGIN INLINE COPY OF scripts/lib/fan-eligibility.js — DO NOT EDIT HERE
//       ...identical function bodies...
//       // <<< END INLINE COPY
//
//   TODO(sub-build 3): add a check to scripts/ci/validate.sh that extracts the
//   inlined block from campaign.js and asserts it is character-identical to the
//   canonical bodies in THIS file. Until campaign.js exists there is nothing to
//   diff against, so the CI assertion is deferred — this comment IS the contract.
//   If you edit the logic below, you MUST re-inline it into campaign.js.
//
// This file itself is authored as a plain node-runnable CommonJS module ONLY so
// it can be unit-tested in isolation. It uses Node built-ins / language only —
// zero external dependencies, zero I/O, fully deterministic and pure.
// =============================================================================
//
// BIAS-TO-SERIALIZE DOCTRINE (the reason this whole file is paranoid):
//   A wrong "eligible:true" lets tracks fan out in parallel and can CORRUPT
//   shared state — an irreversible, expensive-to-debug failure.
//   A wrong "eligible:false" only costs wall-clock time (we run serially).
//   The costs are wildly asymmetric, so EVERY ambiguous case resolves to
//   ineligible / CONFLICT. We never "prove" disjointness by optimistic
//   assumption; we only return eligible:true when disjointness is provable
//   from concrete, non-glob path segments.

// Glob metacharacters that make a segment non-literal (and thus un-provable).
const GLOB_CHARS_RE = /[*?[\]]/;

function isGlobSegment(seg) {
  return GLOB_CHARS_RE.test(seg);
}

// -----------------------------------------------------------------------------
// normalizePath — canonicalize a declared path so comparisons are stable.
//   - POSIX separators (backslashes -> '/')
//   - collapse duplicate '/' into one
//   - strip leading './' (repeatedly)
//   - strip trailing '/'
// Null/undefined/non-string inputs collapse to '' so they get caught by the
// "too broad" gate below (serialize on garbage input — never fan).
// -----------------------------------------------------------------------------
function normalizePath(p) {
  let s = p == null ? '' : String(p);
  s = s.replace(/\\/g, '/'); // POSIX separators
  s = s.replace(/\/+/g, '/'); // collapse duplicate slashes
  while (s.startsWith('./')) {
    s = s.slice(2);
  }
  if (s.length > 1 && s.endsWith('/')) {
    s = s.slice(0, -1);
  }
  return s;
}

// -----------------------------------------------------------------------------
// pathsConflict — do two NORMALIZED paths possibly touch a common file?
//
// Compared by PATH SEGMENTS (never raw string prefix), so 'src/foo' does not
// falsely conflict with 'src/foo-bar', but 'src/foo' does conflict with
// 'src/foo/bar.js' and with 'src'.
//
// File-vs-directory: a path whose last segment carries a literal extension
// (a dot, no glob chars) reads as a FILE; otherwise it reads as a DIRECTORY
// prefix. We compute nothing special from this because the segment-nesting
// rule below is STRICTLY MORE CONSERVATIVE than any file/dir distinction:
//   - a directory prefix conflicts with everything nested under it, and
//   - treating a "file" that is nonetheless a strict prefix of a longer path
//     as disjoint would be an optimistic assumption — forbidden by the
//     bias-to-serialize doctrine. So any segment-nesting => CONFLICT.
// The file/dir heuristic can therefore only ever ADD conflicts, never remove
// one, so it collapses into the nesting rule and needs no separate branch.
//
// Algorithm (walk the shared segment depth):
//   * if either segment at depth i is a glob   -> cannot prove they differ -> CONFLICT
//   * if both are literal and DIFFER           -> subtrees provably disjoint -> no conflict
//   * if both are literal and EQUAL            -> keep walking
//   * fell off the end (one is a prefix of the
//     other, or they are identical)            -> nested/equal -> CONFLICT
// -----------------------------------------------------------------------------
function pathsConflict(a, b) {
  const segsA = a.split('/');
  const segsB = b.split('/');
  const depth = Math.min(segsA.length, segsB.length);

  for (let i = 0; i < depth; i++) {
    const sa = segsA[i];
    const sb = segsB[i];
    if (isGlobSegment(sa) || isGlobSegment(sb)) {
      return true; // unsure -> conflict
    }
    if (sa !== sb) {
      return false; // concrete divergence -> disjoint subtrees
    }
  }
  // Identical, or one is a segment-prefix of the other -> conflict.
  return true;
}

// -----------------------------------------------------------------------------
// fanEligibility — THE predicate. Returns { eligible, reason }.
// See rule numbers inline; every "no" path returns a specific reason string.
// -----------------------------------------------------------------------------
function fanEligibility(items, maxFanWidth = 4) {
  const list = Array.isArray(items) ? items : [];
  const width = list.length;

  // Rule 1: nothing to parallelize.
  if (width <= 1) {
    return { eligible: false, reason: 'width<=1' };
  }

  // Rule 2: too wide. NO batching — Athena's explicit call is to serialize.
  if (width > maxFanWidth) {
    return {
      eligible: false,
      reason: `width ${width} > maxFanWidth ${maxFanWidth}`,
    };
  }

  // Rule 3: every item must be explicitly mechanical. Missing/undefined
  // mechanical is treated as NOT mechanical (=== true is the only pass).
  for (const item of list) {
    if (!item || item.mechanical !== true) {
      const id = item ? item.id : undefined;
      return { eligible: false, reason: `item ${id} not mechanical` };
    }
  }

  // Rule 4: every item must declare a non-empty paths[].
  for (const item of list) {
    if (!Array.isArray(item.paths) || item.paths.length === 0) {
      return { eligible: false, reason: `item ${item.id} declares no paths[]` };
    }
  }

  // Rules 5 + 6: normalize every path, then reject anything too broad to prove
  // disjoint. A repo-wide / leading-glob path effectively touches everything.
  const normalizedByItem = list.map((item) => ({
    id: item.id,
    paths: item.paths.map(normalizePath),
  }));

  for (const item of normalizedByItem) {
    for (const p of item.paths) {
      const firstSeg = p.split('/')[0];
      if (
        p === '' ||
        p === '.' ||
        p === '*' ||
        p === '**' ||
        p.startsWith('**') ||
        firstSeg === '*' ||
        firstSeg === '**'
      ) {
        return {
          eligible: false,
          reason: `item ${item.id} path '${p}' is too broad to prove disjoint`,
        };
      }
    }
  }

  // Rule 7: pairwise disjointness across ALL items (every pair, every
  // path-vs-path). conflict is symmetric, so i<j covers both directions.
  for (let i = 0; i < normalizedByItem.length; i++) {
    for (let j = i + 1; j < normalizedByItem.length; j++) {
      const A = normalizedByItem[i];
      const B = normalizedByItem[j];
      for (const pa of A.paths) {
        for (const pb of B.paths) {
          if (pathsConflict(pa, pb)) {
            return {
              eligible: false,
              reason: `item ${A.id} path '${pa}' overlaps item ${B.id} path '${pb}'`,
            };
          }
        }
      }
    }
  }

  // Rule 8: only now is a fan provably safe.
  return {
    eligible: true,
    reason: `width ${width}, all mechanical, disjoint paths`,
  };
}

// Helpers are exported so tests can hit normalize / conflict edge cases directly.
module.exports = { fanEligibility, normalizePath, pathsConflict };
