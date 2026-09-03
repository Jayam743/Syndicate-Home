#!/usr/bin/env python3
"""recall-index.py — SQLite FTS5/BM25 index for Syndicate recall.

Backs scripts/recall.sh Part 1. Indexes the EXISTING session transcripts
(~/.claude/projects/**/*.jsonl) into an FTS5 table and answers keyword queries
ranked by BM25 (not raw match-count).

Subcommands:
  probe                          exit 0 iff sqlite3 with FTS5 is available
  index  --db DB --projects DIR  build/update the index (self-heal path)
  query  --db DB TERM [TERM..]   print "mtime<TAB>score<TAB>path" for matches

Contract (Athena guardrails):
  * python3 stdlib only; no sqlite3 CLI dependency.
  * query never throws on path/hyphen/quote terms — every term is sanitized and
    wrapped as an FTS5 quoted phrase.
  * index is atomic: cold build goes to a temp db then os.replace() onto the live
    path (same fs); incremental runs in a single transaction. Mid-run death leaves
    no partial/corrupt live index. WAL is enabled.
  * QUIET on index: nothing to stdout (query prints results; index prints nothing).
  * Distinguishable states via query exit code:
      0  searched (ran a MATCH) — zero lines means honest corpus-miss
      3  index unavailable (db/table missing or empty) — caller falls back to grep
      2  error (corrupt/unusable db) — caller falls back to grep
"""

import os
import sys
import time
import sqlite3

BUSY_TIMEOUT_MS = 5000
QUERY_LIMIT = 200


def _connect(path):
    conn = sqlite3.connect(path, timeout=BUSY_TIMEOUT_MS / 1000.0)
    conn.execute("PRAGMA busy_timeout=%d" % BUSY_TIMEOUT_MS)
    return conn


def _ensure_schema(conn):
    conn.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS docs "
        "USING fts5(path UNINDEXED, mtime UNINDEXED, content)"
    )
    conn.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")


def _enable_wal(conn):
    conn.execute("PRAGMA journal_mode=WAL")


def _get_last(conn):
    try:
        row = conn.execute(
            "SELECT value FROM meta WHERE key='last_index'"
        ).fetchone()
        return int(row[0]) if row else 0
    except (sqlite3.Error, ValueError):
        return 0


def _set_last(conn, epoch):
    conn.execute(
        "INSERT OR REPLACE INTO meta(key, value) VALUES('last_index', ?)",
        (str(int(epoch)),),
    )


def _iter_jsonl(projects_dir):
    for root, _dirs, files in os.walk(projects_dir):
        for name in files:
            if name.endswith(".jsonl"):
                yield os.path.join(root, name)


def _reindex(conn, files):
    """Upsert the given files. FTS5 has no UNIQUE(path), so delete-then-insert."""
    cur = conn.cursor()
    for f in files:
        try:
            mtime = int(os.stat(f).st_mtime)
            with open(f, "rb") as fh:
                content = fh.read().decode("utf-8", "replace")
        except OSError:
            continue
        cur.execute("DELETE FROM docs WHERE path=?", (f,))
        cur.execute(
            "INSERT INTO docs(path, mtime, content) VALUES(?, ?, ?)",
            (f, mtime, content),
        )


def _index_usable(db):
    """True iff the live db exists, has a docs table, and is non-empty."""
    if not os.path.exists(db):
        return False
    try:
        conn = _connect(db)
    except sqlite3.Error:
        return False
    try:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='docs'"
        ).fetchone()
        if not row:
            return False
        return conn.execute("SELECT count(*) FROM docs").fetchone()[0] > 0
    except sqlite3.Error:
        return False
    finally:
        conn.close()


def cmd_probe():
    try:
        conn = sqlite3.connect(":memory:")
        conn.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
        conn.close()
        return 0
    except sqlite3.Error:
        return 1


def cmd_index(db, projects):
    if not os.path.isdir(projects):
        return 0  # nothing to index; not an error
    os.makedirs(os.path.dirname(db) or ".", exist_ok=True)
    start = int(time.time())

    try:
        if _index_usable(db):
            # Incremental: only files touched since the last successful index.
            conn = _connect(db)
            try:
                _ensure_schema(conn)
                _enable_wal(conn)
                last = _get_last(conn)
                changed = [
                    f for f in _iter_jsonl(projects)
                    if _safe_mtime(f) > last
                ]
                conn.execute("BEGIN")
                _reindex(conn, changed)
                _set_last(conn, start)
                conn.commit()
            finally:
                conn.close()
        else:
            # Cold build into a temp db, then atomic replace onto the live path.
            tmp = "%s.tmp.%d" % (db, os.getpid())
            _cleanup_db_files(tmp)
            conn = _connect(tmp)
            try:
                _ensure_schema(conn)
                _enable_wal(conn)
                conn.execute("BEGIN")
                _reindex(conn, _iter_jsonl(projects))
                _set_last(conn, start)
                conn.commit()
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                conn.close()
            os.replace(tmp, db)
            # Temp WAL/SHM sidecars are empty post-checkpoint; drop them.
            _cleanup_sidecars(tmp)
        return 0
    except sqlite3.OperationalError:
        # Another session holds the write lock — its run covers us. Quiet no-op.
        return 0
    except sqlite3.Error:
        return 2


def _safe_mtime(f):
    try:
        return int(os.stat(f).st_mtime)
    except OSError:
        return 0


def _cleanup_sidecars(base):
    for suffix in ("-wal", "-shm"):
        try:
            os.remove(base + suffix)
        except OSError:
            pass


def _cleanup_db_files(base):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(base + suffix)
        except OSError:
            pass


def _build_match(terms):
    """Wrap each term as an FTS5 quoted-phrase PREFIX query, OR-joined (any-term match).

    Mirrors the grep fallback's case-insensitive SUBSTRING semantics as closely as
    FTS5 allows: the trailing `*` makes each phrase a prefix match, so `auth`/`timeout`
    surface `authentication`/`timeouts` (plurals, compounds, morphological variants) —
    without this, BM25's exact-token match silently reduces recall below the grep path
    and emits a false "no past sessions mention X". Embedded double-quotes are dropped
    so the MATCH grammar can never be broken by a `"`/`*`/`AND` in a term. Paths (src/x)
    and hyphenated ids (auth-timeout) become adjacency phrases — valid FTS5, never a
    syntax error.
    """
    parts = []
    for t in terms:
        t = t.replace('"', " ").strip()
        if t:
            parts.append('"%s"*' % t)
    return " OR ".join(parts)


def cmd_query(db, terms):
    if not os.path.exists(db):
        return 3
    try:
        conn = _connect(db)
    except sqlite3.Error:
        return 2
    try:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='docs'"
        ).fetchone()
        if not row:
            return 3
        if conn.execute("SELECT count(*) FROM docs").fetchone()[0] == 0:
            return 3
        match = _build_match(terms)
        if not match:
            return 3
        rows = conn.execute(
            "SELECT path, mtime, bm25(docs) AS rank FROM docs "
            "WHERE docs MATCH ? ORDER BY rank LIMIT ?",
            (match, QUERY_LIMIT),
        ).fetchall()
        out = sys.stdout
        for path, mtime, rank in rows:
            # bm25() is more-negative == more-relevant; negate so HIGHER == better,
            # matching recall.sh's `sort -k2,2nr` (score desc, mtime desc tiebreak).
            out.write("%s\t%.6f\t%s\n" % (mtime, -rank, path))
        return 0
    except sqlite3.Error:
        return 2
    finally:
        conn.close()


def _arg(argv, flag):
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv):
            return argv[i + 1]
    return None


def main(argv):
    if not argv:
        sys.stderr.write("usage: recall-index.py {probe|index|query} ...\n")
        return 2
    cmd = argv[0]
    rest = argv[1:]
    if cmd == "probe":
        return cmd_probe()
    if cmd == "index":
        db = _arg(rest, "--db")
        projects = _arg(rest, "--projects")
        if not db or not projects:
            sys.stderr.write("index: --db and --projects required\n")
            return 2
        return cmd_index(db, projects)
    if cmd == "query":
        db = _arg(rest, "--db")
        if not db:
            sys.stderr.write("query: --db required\n")
            return 2
        # Strip the "--db DB" pair by position; everything else is a term.
        terms = []
        skip = False
        for i, a in enumerate(rest):
            if skip:
                skip = False
                continue
            if a == "--db":
                skip = True
                continue
            terms.append(a)
        return cmd_query(db, terms)
    sys.stderr.write("unknown subcommand: %s\n" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
