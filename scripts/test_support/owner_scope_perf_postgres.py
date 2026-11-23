"""Read benchmark evidence from disposable PostgreSQL before teardown.

With TENTURA_OWNER_SCOPE_PROBE_DIR set, the benchmark publishes numbered
N.json checkpoints (starting at 0) and waits for N.ack before continuing.
Checkpoints identify a fixture, viewerId, and phase (before, waiting, after).
Publish each JSON file atomically so the observer only reads complete events.
Field checkpoints also identify the iteration (zero-based) and unseenPersonId.
At the waiting checkpoint the real competing operation has been started and
the tag transaction stays open. At the after checkpoint all writes have
finished and the disposable database still exists. The observer reads the
database directly. Checkpoints carry identities and timing barriers only.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid


PROBE_ENV = "TENTURA_OWNER_SCOPE_PROBE_DIR"
TARGET_ENV = "TENTURA_OWNER_SCOPE_CONTENTION_TEST_DB"

INSTALL_AUDIT = """
CREATE SCHEMA owner_scope_perf_audit;
CREATE TABLE owner_scope_perf_audit.writes (
    relation text, viewer text, peer text, backend integer,
    started timestamptz, isolation text
);
CREATE FUNCTION owner_scope_perf_audit.record_write() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO owner_scope_perf_audit.writes
    VALUES (TG_TABLE_NAME, NEW.viewer_id, to_jsonb(NEW)->>'peer_id', pg_backend_pid(),
            transaction_timestamp(), current_setting('transaction_isolation'));
    RETURN NEW;
END;
$$;
CREATE TRIGGER owner_scope_perf_audit AFTER INSERT ON public.person_field_first_seen
FOR EACH ROW EXECUTE FUNCTION owner_scope_perf_audit.record_write();
CREATE TRIGGER owner_scope_perf_audit AFTER INSERT ON public.constellation_anchor_op_log
FOR EACH ROW EXECUTE FUNCTION owner_scope_perf_audit.record_write();
"""

SNAPSHOT = """
SELECT json_build_object(
    'scopeEnforced', current_setting('tentura.owner_scope_enforce', true) = 'on',
    'tagRows', (SELECT count(*) FROM public.person_tag_member WHERE owner_id = :'viewer'),
    'tagOps', (SELECT count(*) FROM public.person_tag_op_log WHERE owner_id = :'viewer'),
    'tagRowsByTransaction', COALESCE((
        SELECT json_object_agg(xid, rows) FROM (
            SELECT xmin::text AS xid, count(*) AS rows
            FROM public.person_tag_member WHERE owner_id = :'viewer' GROUP BY xmin::text
        ) tag_writes
    ), '{}'::json),
    'anchorRowRevision', COALESCE((SELECT max(revision) FROM public.constellation_anchor
                                   WHERE viewer_id = :'viewer'), 0),
    'anchorOps', (SELECT count(*) FROM public.constellation_anchor_op_log WHERE viewer_id = :'viewer'),
    'anchorOpsRepeatableRead', (SELECT count(*) FROM owner_scope_perf_audit.writes
        WHERE relation = 'constellation_anchor_op_log' AND viewer = :'viewer'
          AND isolation = 'repeatable read'),
    'anchorCursor', COALESCE((SELECT revision FROM public.constellation_anchor_cursor
                               WHERE viewer_id = :'viewer'), 0),
    'firstSeen', EXISTS (SELECT FROM public.person_field_first_seen
                         WHERE viewer_id = :'viewer' AND peer_id = :'person'),
    'firstSeenWriters', COALESCE((
        SELECT json_agg(json_build_array(backend, started)) FROM owner_scope_perf_audit.writes
        WHERE relation = 'person_field_first_seen' AND viewer = :'viewer' AND peer = :'person'
    ), '[]'::json)
)
"""


TAG_WRITER_BLOCKS_OWNER_OPERATION = """
WITH owner_lock AS (
    SELECT hashtextextended('owner_graph:' || :'viewer', 4242) AS key,
           oid AS database
    FROM pg_database WHERE datname = current_database()
)
SELECT json_build_object('writerXid', writer.backend_xid::text,
                         'waitingTransaction', json_build_array(waiting.pid, activity.xact_start))
    FROM owner_lock k
    JOIN pg_locks waiting ON waiting.database = k.database
        AND waiting.locktype = 'advisory' AND waiting.objsubid = 1
        AND waiting.classid::bigint = ((k.key >> 32) & 4294967295)
        AND waiting.objid::bigint = (k.key & 4294967295)
    JOIN pg_locks holder ON holder.database = waiting.database
        AND holder.locktype = waiting.locktype AND holder.objsubid = waiting.objsubid
        AND holder.classid = waiting.classid AND holder.objid = waiting.objid
    JOIN pg_stat_activity activity ON activity.pid = waiting.pid
        AND activity.datname = current_database()
    JOIN pg_stat_activity writer ON writer.pid = holder.pid AND writer.datname = current_database()
    WHERE NOT waiting.granted AND holder.granted
      AND writer.backend_xid IS NOT NULL
      AND holder.pid = ANY(pg_blocking_pids(waiting.pid))
      AND activity.query LIKE '%pg_advisory_xact_lock%'
      AND EXISTS (
          SELECT FROM pg_locks tag
          WHERE tag.database = k.database AND tag.pid = holder.pid
            AND tag.locktype = 'relation' AND tag.granted AND tag.mode = 'RowExclusiveLock'
            AND tag.relation = 'public.person_tag_member'::regclass
      )
LIMIT 1
"""


def query(database, sql, viewer, person, deadline, *, read_only=True):
    env = {
        **os.environ,
        "PGPASSWORD": os.environ.get("POSTGRES_PASSWORD", "password"),
        "PGCONNECT_TIMEOUT": "2",
        "PGOPTIONS": f"-c statement_timeout=2000 -c default_transaction_read_only={'on' if read_only else 'off'}",
    }
    host = os.environ.get("POSTGRES_HOST", "127.0.0.1")
    port = os.environ.get("POSTGRES_PORT", "5432")
    client = ["psql"]
    if not shutil.which("psql") and host in {"127.0.0.1", "localhost"}:
        container = {"5432": "postgres", "5433": "postgres-test"}.get(port)
        if container:
            client = ["docker", "exec", "-i", "-e", "PGPASSWORD", "-e", "PGCONNECT_TIMEOUT",
                      "-e", "PGOPTIONS", container, "psql"]
            host, port = "127.0.0.1", "5432"
    result = subprocess.run(
        [*client, "-XAtqw", "-v", "ON_ERROR_STOP=1", "-v", f"viewer={viewer}",
         "-v", f"person={person}", "-h", host, "-p", port, "-d", database,
        "-U", os.environ.get("POSTGRES_USERNAME", "postgres")],
        input=sql, capture_output=True, text=True, env=env, check=True,
        timeout=min(3, max(0.01, deadline - time.monotonic())),
    )
    return result.stdout.strip()


def read_checkpoint(database, event):
    viewer = event["viewerId"]
    person = event.get("unseenPersonId", "")
    lock = None
    deadline = time.monotonic() + 3
    if event["phase"] == "waiting":
        deadline = time.monotonic() + 5.5
        while time.monotonic() < deadline:
            observed = query(database, TAG_WRITER_BLOCKS_OWNER_OPERATION, viewer, person, deadline)
            if observed:
                lock = json.loads(observed)
                break
            time.sleep(0.02)
        else:
            raise AssertionError(f"PostgreSQL showed no owner-lock wait behind the tag writer: {event}")

    state = query(database, SNAPSHOT, viewer, person, deadline)
    return {**event, "state": json.loads(state), "lock": lock}


def run_with_postgres_probe(command, cwd, environment, timeout):
    database = f"tentura_test_owner_probe_{uuid.uuid4().hex}"
    observations = []
    with tempfile.TemporaryDirectory(prefix="owner-scope-perf-") as directory:
        env = {**environment, PROBE_ENV: directory, TARGET_ENV: database}
        with tempfile.TemporaryFile(mode="w+t", encoding="utf-8") as output:
            with subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                  stderr=subprocess.STDOUT, text=True) as process:
                deadline = time.monotonic() + timeout

                def read_output():
                    output.seek(0)
                    return output.read()

                try:
                    while process.poll() is None:
                        if time.monotonic() >= deadline:
                            raise AssertionError("Timed out observing the PostgreSQL benchmark")
                        checkpoint = Path(directory) / f"{len(observations)}.json"
                        if not checkpoint.exists():
                            time.sleep(0.02)
                            continue
                        event = json.loads(checkpoint.read_text(encoding="utf-8"))
                        if not observations:
                            if event["phase"] != "before":
                                raise AssertionError(f"Expected an initial database checkpoint: {event}")
                            query(database, INSTALL_AUDIT, "", "", time.monotonic() + 3, read_only=False)
                        observations.append(read_checkpoint(database, event))
                        checkpoint.with_suffix(".ack").touch()
                    return process.returncode, read_output(), observations
                except (AssertionError, KeyError, OSError, TypeError, ValueError,
                        subprocess.SubprocessError) as error:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                    detail = getattr(error, "stderr", None) or str(error)
                    raise AssertionError(f"{detail}\n{read_output()}") from error
