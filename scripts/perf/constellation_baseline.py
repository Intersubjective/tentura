#!/usr/bin/env python3
"""Constellation server baseline (issue #235 U41): FULL, ANCHORS, person upsert
and delete, cold and warm, with a bootstrap confidence interval on every p95.

Needs the local server running against the dataset under test
(`scripts/perf/run_server_db.sh <db>`) with MeritRank loaded for that database
(`SELECT mr_reset(); SELECT meritrank_init();`), and a QA email credential for
every viewer. Latency is wall-clock from the client's request to the end of the
response body on loopback, so it covers admission, the transaction and response
encoding.

Cold = MeritRank peer-frame cache emptied right before the call
(`mr_reset(); meritrank_init()` in --db, the state after an MR restart).
Warm = the same viewer repeated after warm-up calls.

Usage:
  constellation_baseline.py --db tentura_perfsynth --label perfsynth \
      --viewers perf-heavy@test.tentura.local perf-synth-1@test.tentura.local ... \
      --warm-n 60 --cold-n 30 --out packages/server/build/perf/u41_perfsynth.json
"""
import argparse, json, random, statistics, subprocess, sys, time
import constellation_gql_bench as bench

BASE = "http://127.0.0.1:2080"
BOOTSTRAP = 5000


def pct(xs, q):
    xs = sorted(xs)
    pos = (len(xs) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)


def p95_ci(xs, rng):
    """95% percentile-bootstrap interval of the sample p95."""
    stats = sorted(pct([rng.choice(xs) for _ in xs], 0.95) for _ in range(BOOTSTRAP))
    return stats[int(0.025 * BOOTSTRAP)], stats[int(0.975 * BOOTSTRAP) - 1]


def summarise(xs, rng):
    lo, hi = p95_ci(xs, rng)
    return {"n": len(xs), "p50": pct(xs, 0.5), "p95": pct(xs, 0.95), "p95_ci": [lo, hi],
            "min": min(xs), "max": max(xs), "mean": statistics.mean(xs)}


def reset_mr(db):
    subprocess.run(["docker", "exec", "postgres", "psql", "-U", "postgres", "-d", db, "-Atc",
                    "select mr_reset(); select meritrank_init();"],
                   check=True, capture_output=True)


def edge_count(db):
    out = subprocess.run(["docker", "exec", "postgres", "psql", "-U", "postgres", "-d", db, "-Atc",
                          "select count(*) from mr_edgelist()"], check=True, capture_output=True, text=True)
    return int(out.stdout.strip())


UPSERT = ('mutation($x:Float!,$y:Float!){ constellationAnchorUpsert(targetKind:PERSON,targetId:"%s",'
          'xUnits:$x,yUnits:$y,coordinateSpaceVersion:1){ revision } }')
DELETE = 'mutation{ constellationAnchorDelete(targetKind:PERSON,targetId:"%s"){ revision } }'


class Viewer:
    def __init__(self, email):
        self.email = email
        self.client = bench.Client(bench.login(email, BASE))
        _, j, size = self.client.call(bench.field("FULL"))
        f = j["data"]["constellationField"]
        self.peers = f["peers"]
        self.peer = next(p["id"] for p in f["peers"] if p["id"])
        self.shape = {"payload_bytes": size, "peers": len(f["peers"]), "requests": len(f["requests"]),
                      "edges": len(f["edges"]), "peers_capped": f["peersCapped"],
                      "requests_capped": f["requestsCapped"]}

    def full(self):
        return self.client.call(bench.field("FULL"))[0]

    def anchors(self):
        return self.client.call(bench.field("ANCHORS"))[0]

    def upsert(self, i=0):
        return self.client.call(UPSERT % self.peer, {"x": 1.0 + (i % 5) * 0.1, "y": 2.0})[0]

    def delete(self):
        return self.client.call(DELETE % self.peer)[0]


def warm(viewer, n, rng):
    for _ in range(5):
        viewer.full(); viewer.anchors()
    viewer.upsert(); viewer.delete()
    full = [viewer.full() for _ in range(n)]
    anchors = [viewer.anchors() for _ in range(n)]
    upsert, delete = [], []
    for i in range(n):
        upsert.append(viewer.upsert(i))
        delete.append(viewer.delete())
    return {"FULL": full, "ANCHORS": anchors, "upsert": upsert, "delete": delete}


def cold(viewers, db, n):
    out = {"FULL": [], "ANCHORS": [], "upsert": [], "delete": []}
    for i in range(n):
        v = viewers[i % len(viewers)]
        reset_mr(db); out["FULL"].append(v.full())
        reset_mr(db); out["ANCHORS"].append(v.anchors())
        reset_mr(db); out["upsert"].append(v.upsert(i)); v.delete()
        v.upsert(i); reset_mr(db); out["delete"].append(v.delete())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--viewers", nargs="+", required=True)
    ap.add_argument("--warm-n", type=int, default=60)
    ap.add_argument("--cold-n", type=int, default=30)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rng = random.Random(235)
    edges = edge_count(a.db)
    if edges == 0:
        sys.exit("mr_edgelist() is empty: run mr_reset(); meritrank_init() first")
    viewers = [Viewer(e) for e in a.viewers]
    t0 = time.time()
    warm_samples = warm(viewers[0], a.warm_n, rng)
    cold_samples = cold(viewers, a.db, a.cold_n)
    reset_mr(a.db)
    result = {"label": a.label, "db": a.db, "mr_edges": edges, "viewers": [v.email for v in viewers],
              "shape_first_viewer": viewers[0].shape, "warm_n": a.warm_n, "cold_n": a.cold_n,
              "elapsed_s": round(time.time() - t0), "bootstrap": BOOTSTRAP,
              "warm": {k: summarise(v, rng) for k, v in warm_samples.items()},
              "cold": {k: summarise(v, rng) for k, v in cold_samples.items()},
              "raw": {"warm": warm_samples, "cold": cold_samples}}
    json.dump(result, open(a.out, "w"), indent=1)
    for temp in ("cold", "warm"):
        for op, s in result[temp].items():
            print(f"{a.label} {op:8s} {temp} n={s['n']} p50={s['p50']:.1f} p95={s['p95']:.1f} "
                  f"CI95=[{s['p95_ci'][0]:.1f}, {s['p95_ci'][1]:.1f}] max={s['max']:.1f}")


if __name__ == "__main__":
    main()
