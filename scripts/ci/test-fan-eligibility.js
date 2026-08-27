'use strict';
// =============================================================================
// test-fan-eligibility.js — exhaustive unit tests for fan-eligibility.js
//
// Safety note: a wrong eligible:true lets non-disjoint tracks fan into
// worktrees and corrupt shared state. Every test that expects eligible:false
// sets falseEligibleFound=true if it gets eligible:true instead, and the
// process exits non-zero so CI blocks.
// =============================================================================

const path = require('path');
const { fanEligibility, normalizePath, pathsConflict } = require(
  path.join(__dirname, '../lib/fan-eligibility.js')
);

let passed = 0;
let failed = 0;
const failures = [];
let falseEligibleFound = false;

// ---------------------------------------------------------------------------
// Assertion helpers
// ---------------------------------------------------------------------------

function assert(name, condition, detail) {
  if (condition) {
    passed++;
    process.stdout.write('  PASS  ' + name + '\n');
  } else {
    failed++;
    const msg = detail != null ? ': ' + String(detail) : '';
    process.stdout.write('  FAIL  ' + name + msg + '\n');
    failures.push({ name, detail: detail != null ? String(detail) : '' });
  }
}

function assertEqual(name, actual, expected) {
  const ok = actual === expected;
  assert(
    name,
    ok,
    ok ? undefined : 'expected ' + JSON.stringify(expected) + ', got ' + JSON.stringify(actual)
  );
}

/**
 * Assert fanEligibility returns eligible:false AND reason contains fragment.
 * If eligible:true is returned when false was expected → CRITICAL bug, set flag.
 */
function assertIneligible(name, result, reasonFragment) {
  if (result.eligible === true) {
    falseEligibleFound = true;
    failed++;
    failures.push({
      name,
      detail: 'CRITICAL FALSE-ELIGIBLE: got eligible:true; reason=' + result.reason,
    });
    process.stdout.write(
      '  FAIL  [CRITICAL FALSE-ELIGIBLE] ' + name + '\n' +
      '        got: eligible=true, reason=' + result.reason + '\n'
    );
    return;
  }
  const reasonOk = result.reason.includes(reasonFragment);
  assert(
    name,
    !result.eligible && reasonOk,
    reasonOk
      ? undefined
      : 'reason must include "' + reasonFragment + '", got "' + result.reason + '"'
  );
}

function assertEligible(name, result) {
  assert(
    name,
    result.eligible === true,
    result.eligible ? undefined : 'got ineligible: ' + result.reason
  );
}

/** Make a mechanical item (shorthand for the common case). */
function mitem(id, paths) {
  return { id, mechanical: true, paths };
}

// ---------------------------------------------------------------------------
// SECTION 1: Width Gates
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 1: Width Gates ===\n');

assertIneligible(
  'width=0 (empty array) -> ineligible',
  fanEligibility([]),
  'width<=1'
);

assertIneligible(
  'width=1 (single item) -> ineligible',
  fanEligibility([mitem('a', ['src/a.js'])]),
  'width<=1'
);

assertEligible(
  'width=2, mechanical, disjoint -> eligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
  ])
);

assertEligible(
  'width=3, mechanical, disjoint -> eligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
  ])
);

assertEligible(
  'width=4, mechanical, disjoint -> eligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
    mitem('d', ['docs/d.md']),
  ])
);

assertIneligible(
  'width=5, default maxFanWidth=4 -> ineligible (no batching)',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
    mitem('d', ['docs/d.md']),
    mitem('e', ['tests/e.js']),
  ]),
  'width 5 > maxFanWidth 4'
);

// Verify reason is exact — "width > maxFanWidth" pattern
(function () {
  const r = fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
    mitem('d', ['docs/d.md']),
    mitem('e', ['tests/e.js']),
  ]);
  assert(
    'width=5 reason contains literal width and maxFanWidth values',
    r.reason === 'width 5 > maxFanWidth 4',
    'got: ' + r.reason
  );
}());

// Custom maxFanWidth: width=5 with maxFanWidth=5 is eligible when items are fine
assertEligible(
  'width=5, maxFanWidth=5 (custom) -> eligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
    mitem('d', ['docs/d.md']),
    mitem('e', ['tests/e.js']),
  ], 5)
);

// Width=2 with maxFanWidth=1 is still ineligible (width > maxFanWidth)
assertIneligible(
  'width=2, maxFanWidth=1 -> ineligible (width > maxFanWidth)',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
  ], 1),
  'width 2 > maxFanWidth 1'
);

// Non-array input collapses to [] -> width<=1
assertIneligible('null items -> width<=1', fanEligibility(null), 'width<=1');
assertIneligible('undefined items -> width<=1', fanEligibility(undefined), 'width<=1');
assertIneligible('string items -> width<=1', fanEligibility('oops'), 'width<=1');

// ---------------------------------------------------------------------------
// SECTION 2: Mechanical Gate
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 2: Mechanical Gate ===\n');

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'beta', mechanical: false, paths: ['src/b.js'] },
  ]);
  assertIneligible('mechanical:false -> ineligible', r, 'beta');
  assert(
    'mechanical:false reason includes "not mechanical"',
    r.reason.includes('not mechanical'),
    r.reason
  );
}());

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'gamma', paths: ['src/b.js'] },  // mechanical key absent
  ]);
  assertIneligible('mechanical:undefined -> ineligible, names item', r, 'gamma');
  assert(
    'mechanical:undefined reason includes "not mechanical"',
    r.reason.includes('not mechanical'),
    r.reason
  );
}());

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'delta', mechanical: null, paths: ['src/b.js'] },
  ]);
  assertIneligible('mechanical:null -> ineligible, names item', r, 'delta');
}());

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'epsilon', mechanical: 1, paths: ['src/b.js'] },  // truthy but not === true
  ]);
  assertIneligible('mechanical:1 (not === true) -> ineligible, names item', r, 'epsilon');
}());

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'zeta', mechanical: 'true', paths: ['src/b.js'] },  // string "true" not === true
  ]);
  assertIneligible('mechanical:"true" (string) -> ineligible, names item', r, 'zeta');
}());

// ---------------------------------------------------------------------------
// SECTION 3: Paths Gate
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 3: Paths Gate ===\n');

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    mitem('empty-paths', []),
  ]);
  assertIneligible('paths:[] -> ineligible, names item', r, 'empty-paths');
  assert(
    'paths:[] reason includes "declares no paths[]"',
    r.reason.includes('declares no paths[]'),
    r.reason
  );
}());

(function () {
  const r = fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'no-paths-key', mechanical: true },  // paths key absent
  ]);
  assertIneligible('paths key absent -> ineligible, names item', r, 'no-paths-key');
  assert(
    'paths absent reason includes "declares no paths[]"',
    r.reason.includes('declares no paths[]'),
    r.reason
  );
}());

assertIneligible(
  'paths:null -> ineligible, names item',
  fanEligibility([
    mitem('alpha', ['src/a.js']),
    { id: 'null-paths', mechanical: true, paths: null },
  ]),
  'null-paths'
);

// ---------------------------------------------------------------------------
// SECTION 4: normalizePath
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 4: normalizePath ===\n');

assertEqual("normalize: './src/a.js' -> 'src/a.js'",    normalizePath('./src/a.js'),    'src/a.js');
assertEqual("normalize: 'src/a.js/' -> 'src/a.js'",      normalizePath('src/a.js/'),    'src/a.js');
assertEqual("normalize: 'src\\\\a.js' -> 'src/a.js'",    normalizePath('src\\a.js'),    'src/a.js');
assertEqual("normalize: 'src//a.js' -> 'src/a.js'",      normalizePath('src//a.js'),    'src/a.js');
assertEqual("normalize: null -> ''",                       normalizePath(null),           '');
assertEqual("normalize: undefined -> ''",                  normalizePath(undefined),      '');
assertEqual("normalize: '' -> ''",                         normalizePath(''),             '');
assertEqual("normalize: './././src/a.js' -> 'src/a.js'",  normalizePath('./././src/a.js'), 'src/a.js');
assertEqual("normalize: 'src\\\\foo\\\\bar.js' -> 'src/foo/bar.js'",
  normalizePath('src\\foo\\bar.js'), 'src/foo/bar.js');
assertEqual("normalize: '.' -> '.'",                       normalizePath('.'),            '.');
assertEqual("normalize: 'src///a.js' -> 'src/a.js'",      normalizePath('src///a.js'),  'src/a.js');
// trailing slash stripped only when length > 1
assertEqual("normalize: 'src/foo/' -> 'src/foo'",          normalizePath('src/foo/'),    'src/foo');

// ---------------------------------------------------------------------------
// SECTION 5: Broad-Glob Rejection
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 5: Broad-Glob Rejection ===\n');

function broadGlobItem(p) {
  return fanEligibility([
    mitem('ref', ['src/a.js']),
    mitem('broad', [p]),
  ]);
}

assertIneligible("broad-glob: '' -> ineligible 'too broad'",       broadGlobItem(''),        'too broad');
assertIneligible("broad-glob: '.' -> ineligible 'too broad'",      broadGlobItem('.'),       'too broad');
assertIneligible("broad-glob: '*' -> ineligible 'too broad'",      broadGlobItem('*'),       'too broad');
assertIneligible("broad-glob: '**' -> ineligible 'too broad'",     broadGlobItem('**'),      'too broad');
assertIneligible("broad-glob: '**/x.js' -> ineligible 'too broad'",broadGlobItem('**/x.js'), 'too broad');
assertIneligible("broad-glob: '*/foo' (firstSeg=*) -> ineligible 'too broad'",
  broadGlobItem('*/foo'), 'too broad');

// Verify the reason string names the broad path itself
(function () {
  const r = broadGlobItem('*');
  assert(
    "broad-glob reason names the offending path '*'",
    r.reason.includes("path '*' is too broad"),
    r.reason
  );
}());

// ---------------------------------------------------------------------------
// SECTION 6: pathsConflict Disjointness Matrix
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 6: pathsConflict Disjointness Matrix ===\n');

// Helpers
function expectConflict(label, a, b) {
  const got = pathsConflict(a, b);
  assert(label, got === true, got ? undefined : 'expected CONFLICT, got DISJOINT');
}
function expectDisjoint(label, a, b) {
  const got = pathsConflict(a, b);
  // If pathsConflict returns true (CONFLICT) when we expect DISJOINT,
  // this is over-conservative (safe but costs wall-clock). Not a
  // false-eligible scenario, so we do NOT set falseEligibleFound here.
  assert(label, got === false, got ? 'expected DISJOINT, got CONFLICT (over-conservative)' : undefined);
}

// Identical paths
expectConflict("CONFLICT: 'src/a.js' vs 'src/a.js' (identical)", 'src/a.js', 'src/a.js');

// Dir contains file
expectConflict("CONFLICT: 'src' vs 'src/a.js' (dir prefix)",           'src',     'src/a.js');
expectConflict("CONFLICT: 'src/a.js' vs 'src' (reverse dir prefix)",   'src/a.js', 'src');
expectConflict("CONFLICT: 'src/foo' vs 'src/foo/bar.js' (nested)",      'src/foo', 'src/foo/bar.js');
expectConflict("CONFLICT: 'src/foo/bar.js' vs 'src/foo' (reverse)",     'src/foo/bar.js', 'src/foo');

// Siblings — provably disjoint
expectDisjoint("DISJOINT: 'src/a.js' vs 'src/b.js' (filename siblings)", 'src/a.js', 'src/b.js');
expectDisjoint("DISJOINT: 'src/foo' vs 'src/bar' (dir siblings)",         'src/foo',  'src/bar');
expectDisjoint("DISJOINT: 'lib' vs 'src' (root siblings)",                'lib',      'src');

// === FALSE-PREFIX TRAP — the critical safety assertion ===
// Raw string prefix 'src/foo' IS a prefix of 'src/foo-bar', but segment-wise
// they diverge at segment 1 ('foo' vs 'foo-bar'), so they are DISJOINT.
expectDisjoint(
  "FALSE-PREFIX TRAP: 'src/foo' vs 'src/foo-bar' -> DISJOINT (segment-based, NOT string prefix)",
  'src/foo', 'src/foo-bar'
);
expectDisjoint(
  "FALSE-PREFIX TRAP (reverse): 'src/foo-bar' vs 'src/foo' -> DISJOINT",
  'src/foo-bar', 'src/foo'
);
expectDisjoint(
  "FALSE-PREFIX TRAP root: 'lib' vs 'lib-utils' -> DISJOINT",
  'lib', 'lib-utils'
);
expectDisjoint(
  "FALSE-PREFIX TRAP deep: 'a/b/foo' vs 'a/b/foo-bar' -> DISJOINT",
  'a/b/foo', 'a/b/foo-bar'
);

// Glob overlap — cannot prove disjoint -> CONFLICT
expectConflict("CONFLICT: 'src/*' vs 'src/a.js' (glob overlaps literal)",    'src/*', 'src/a.js');
expectConflict("CONFLICT: 'src/a.js' vs 'src/*' (reverse glob)",              'src/a.js', 'src/*');
expectConflict("CONFLICT: '*' vs 'src/a.js' (top-level glob)",                '*',    'src/a.js');
expectConflict("CONFLICT: 'src/foo/*' vs 'src/foo/bar.js' (glob under same dir)", 'src/foo/*', 'src/foo/bar.js');

// Glob with disjoint subtrees: diverge BEFORE hitting the glob segment -> DISJOINT
expectDisjoint(
  "DISJOINT: 'src/foo/*' vs 'src/bar/*' (diverge at foo vs bar before glob)",
  'src/foo/*', 'src/bar/*'
);

// Deep siblings
expectDisjoint("DISJOINT: 'a/b/c.js' vs 'a/b/d.js' (deep siblings)",  'a/b/c.js', 'a/b/d.js');
expectConflict("CONFLICT: 'a/b/c.js' vs 'a/b' (file under dir)",       'a/b/c.js', 'a/b');
expectConflict("CONFLICT: 'a/b' vs 'a/b/c.js' (reverse)",              'a/b',       'a/b/c.js');

// Symmetry spot-checks (conflict is symmetric)
(function () {
  const pairs = [
    ['src/a.js', 'src/b.js'],
    ['src/foo', 'src/foo-bar'],
    ['src', 'src/a.js'],
    ['src/*', 'src/a.js'],
    ['src/foo/*', 'src/bar/*'],
  ];
  for (const [a, b] of pairs) {
    const ab = pathsConflict(a, b);
    const ba = pathsConflict(b, a);
    assert(
      'symmetry: pathsConflict(' + a + ',' + b + ') === pathsConflict(' + b + ',' + a + ')',
      ab === ba,
      'ab=' + ab + ' ba=' + ba
    );
  }
}());

// ---------------------------------------------------------------------------
// SECTION 7: 3-Item Tests via fanEligibility
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 7: 3-Item Tests ===\n');

assertEligible(
  '3 items, all pairwise disjoint -> eligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['lib/c.js']),
  ])
);

// Item c conflicts with item a
(function () {
  const r = fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['src/b.js']),
    mitem('c', ['src/a.js']),  // identical to a
  ]);
  assertIneligible(
    '3 items, a-c overlap -> ineligible naming both paths',
    r,
    "item a path 'src/a.js' overlaps item c path 'src/a.js'"
  );
}());

// Item c is a parent dir of item a's path
(function () {
  const r = fanEligibility([
    mitem('a', ['src/foo/bar.js']),
    mitem('b', ['lib/b.js']),
    mitem('c', ['src/foo']),  // parent dir of a's path
  ]);
  assertIneligible(
    '3 items, c is parent dir of a -> ineligible',
    r,
    'overlaps'
  );
}());

// All three pairwise distinct but two share parent dir
(function () {
  const r = fanEligibility([
    mitem('x', ['src/a.js']),
    mitem('y', ['src/b.js']),
    mitem('z', ['src']),      // parent of both x and y
  ]);
  assertIneligible(
    '3 items, z=src is parent of x and y paths -> ineligible',
    r,
    'overlaps'
  );
}());

// ---------------------------------------------------------------------------
// SECTION 8: Multi-Path Items
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 8: Multi-Path Items ===\n');

assertEligible(
  "multi-path: A=['src/a.js','docs/a.md'], B=['src/b.js','docs/b.md'] -> eligible",
  fanEligibility([
    mitem('A', ['src/a.js', 'docs/a.md']),
    mitem('B', ['src/b.js', 'docs/b.md']),
  ])
);

(function () {
  const r = fanEligibility([
    mitem('A', ['src/a.js', 'docs/a.md']),
    mitem('B', ['src/b.js', 'docs/a.md']),  // docs/a.md shared
  ]);
  assertIneligible(
    "multi-path: docs/a.md shared between A and B -> conflict on docs/a.md",
    r,
    "docs/a.md"
  );
  assert(
    "multi-path: reason names both items A and B",
    r.reason.includes('A') && r.reason.includes('B'),
    r.reason
  );
}());

// Cross-product: A's first path conflicts with B's second
(function () {
  const r = fanEligibility([
    mitem('A', ['src/common.js', 'lib/a.js']),
    mitem('B', ['lib/b.js', 'src/common.js']),  // B's second path = A's first
  ]);
  assertIneligible(
    "multi-path: cross-product conflict on src/common.js -> ineligible",
    r,
    'src/common.js'
  );
}());

// Three items, multi-path, all disjoint
assertEligible(
  "multi-path 3 items, all disjoint -> eligible",
  fanEligibility([
    mitem('A', ['src/a.js', 'docs/a.md']),
    mitem('B', ['src/b.js', 'docs/b.md']),
    mitem('C', ['lib/c.js', 'config/c.json']),
  ])
);

// ---------------------------------------------------------------------------
// SECTION 9: fanEligibility Integration — key conflict cases
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 9: fanEligibility Integration ===\n');

assertIneligible(
  "integration: identical paths 'src/a.js' vs 'src/a.js' -> ineligible",
  fanEligibility([
    mitem('x', ['src/a.js']),
    mitem('y', ['src/a.js']),
  ]),
  'overlaps'
);

assertIneligible(
  "integration: dir 'src' vs nested 'src/a.js' -> ineligible",
  fanEligibility([
    mitem('x', ['src']),
    mitem('y', ['src/a.js']),
  ]),
  'overlaps'
);

// THE KEY FALSE-PREFIX INTEGRATION TEST — must be ELIGIBLE
assertEligible(
  "FALSE-PREFIX TRAP (integration): 'src/foo' vs 'src/foo-bar' -> ELIGIBLE (NOT a conflict)",
  fanEligibility([
    mitem('x', ['src/foo']),
    mitem('y', ['src/foo-bar']),
  ])
);

// Internal glob (not caught by broad-glob gate, but caught by pathsConflict)
assertIneligible(
  "integration: 'src/*' vs 'src/a.js' -> ineligible (glob caught by pathsConflict)",
  fanEligibility([
    mitem('x', ['src/a.js']),
    mitem('y', ['src/*']),
  ]),
  'overlaps'
);

// Paths that look like false-prefix at deeper level
assertEligible(
  "integration: 'a/b/foo' vs 'a/b/foo-bar' -> eligible (deep false-prefix is safe)",
  fanEligibility([
    mitem('x', ['a/b/foo']),
    mitem('y', ['a/b/foo-bar']),
  ])
);

// Path normalization feeds correctly into eligibility
assertEligible(
  "integration: './src/a.js' vs 'src/b.js' -> eligible (normalize strips ./)",
  fanEligibility([
    mitem('x', ['./src/a.js']),
    mitem('y', ['src/b.js']),
  ])
);

assertIneligible(
  "integration: './src/a.js' vs 'src/a.js' -> ineligible (both normalize to src/a.js)",
  fanEligibility([
    mitem('x', ['./src/a.js']),
    mitem('y', ['src/a.js']),
  ]),
  'overlaps'
);

// Entirely distinct top-level dirs
assertEligible(
  "integration: 'frontend/app.js' vs 'backend/server.js' -> eligible",
  fanEligibility([
    mitem('fe', ['frontend/app.js']),
    mitem('be', ['backend/server.js']),
  ])
);

// ---------------------------------------------------------------------------
// SECTION 10: Bias-to-Serialize — ambiguous/edge-case inputs all serialize
// ---------------------------------------------------------------------------
process.stdout.write('\n=== SECTION 10: Bias-to-Serialize Edge Cases ===\n');

// Item with empty string path -> broad-glob caught
assertIneligible(
  'bias: item path is empty string -> ineligible (too broad)',
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['']),
  ]),
  'too broad'
);

// Item with '.' path -> broad-glob caught
assertIneligible(
  "bias: item path is '.' -> ineligible (too broad)",
  fanEligibility([
    mitem('a', ['src/a.js']),
    mitem('b', ['.']),
  ]),
  'too broad'
);

// null item in list: item is falsy -> not mechanical
assertIneligible(
  'bias: null item in list -> ineligible',
  fanEligibility([
    mitem('a', ['src/a.js']),
    null,
  ]),
  'not mechanical'
);

// Completely empty string id — still named in reason
(function () {
  const r = fanEligibility([
    mitem('a', ['src/a.js']),
    { id: '', mechanical: false, paths: ['src/b.js'] },
  ]);
  assert(
    'empty-string id item still marks ineligible',
    r.eligible === false,
    r.reason
  );
}());

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
const total = passed + failed;
process.stdout.write('\n');
process.stdout.write('=================================\n');
if (failed === 0) {
  process.stdout.write('PASS — ' + total + ' tests run, ' + passed + ' passed, 0 failed\n');
} else {
  process.stdout.write('FAIL — ' + total + ' tests run, ' + passed + ' passed, ' + failed + ' failed\n');
  process.stdout.write('\nFailures:\n');
  for (const f of failures) {
    process.stdout.write('  - ' + f.name + (f.detail ? ': ' + f.detail : '') + '\n');
  }
}

if (falseEligibleFound) {
  process.stdout.write('\nCRITICAL: falseEligibleFound=true — at least one CONFLICT was wrongly declared eligible\n');
}

const jsonResult = {
  passed,
  testsRun: total,
  testsFailed: failed,
  failures,
  summary: failed === 0
    ? 'PASS — ' + total + ' tests run, ' + passed + ' passed, 0 failed'
    : 'FAIL — ' + total + ' tests run, ' + passed + ' passed, ' + failed + ' failed',
  testFilePath: __filename,
  falseEligibleFound,
};

process.stdout.write('\nJSON_RESULT: ' + JSON.stringify(jsonResult, null, 2) + '\n');

process.exitCode = failed > 0 ? 1 : 0;
