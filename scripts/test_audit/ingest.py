#!/usr/bin/env python3
"""Turn collect.sh raw output into build/test_audit/cov/<pkg>/<file>.json.

  python3 scripts/test_audit/ingest.py --pkg server|client [--jobs 4]

Each output: {"file", "ok", "tests":[{name,ms,result,skipped}], "covered":{"lib/x.dart":[lines]}}
"""
import argparse, json, re, subprocess, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GEN = re.compile(r"\.(g|gr|gql|freezed|config|schema|data|var|req)\.dart$|/_g/|/l10n/|\.mocks\.dart$")
PKG_URI = {"package:tentura/": "lib/", "package:tentura_root/": "root/lib/",
           "package:force_directed_graphview/": "fdg/lib/", "package:tentura_server/": "lib/"}


def timings(run_jsonl, pkgdir):
    suites, tests, per = {}, {}, {}
    for ln in run_jsonl.read_text(errors="replace").splitlines():
        try: e = json.loads(ln)
        except ValueError: continue
        t = e.get("type")
        if t == "suite":
            suites[e["suite"]["id"]] = e["suite"]["path"]
        elif t == "testStart":
            tests[e["test"]["id"]] = (e["test"]["name"], e["time"], e["test"].get("suiteID"))
        elif t == "testDone" and not e.get("hidden") and e["testID"] in tests:
            n, t0, sid = tests[e["testID"]]
            p = suites.get(sid)
            if not p or n.startswith("loading "): continue
            try: rel = str(Path(p).resolve().relative_to(pkgdir))
            except ValueError: rel = p
            per.setdefault(rel, []).append(dict(name=n, ms=e["time"] - t0, result=e["result"], skipped=e.get("skipped", False)))
    return per


def norm_key(k):
    for pre, rep in PKG_URI.items():
        if k.startswith(pre): return rep + k[len(pre):]
    return None


def server_cov(vm_json, pkgdir):
    with tempfile.TemporaryDirectory() as td:
        lc = Path(td) / "l.info"
        subprocess.run(["dart", "pub", "global", "run", "coverage:format_coverage", "--lcov", f"--in={vm_json}",
                        f"--out={lc}", "--report-on=lib", "--check-ignore",
                        f"--packages={ROOT/'.dart_tool/package_config.json'}"], cwd=pkgdir, capture_output=True, timeout=600)
        cov, cur = {}, None
        if lc.exists():
            for ln in lc.read_text().splitlines():
                if ln.startswith("SF:"):
                    p = ln[3:]; p = "lib/" + p.split("/lib/", 1)[1] if "/lib/" in p else p
                    cur = p if p.startswith("lib/") and not GEN.search(p) else None
                    if cur: cov.setdefault(cur, [])
                elif ln.startswith("DA:") and cur:
                    l, h = ln[3:].split(",")[:2]
                    if int(h) > 0: cov[cur].append(int(l))
        return {k: v for k, v in cov.items() if v}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--pkg", required=True); ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    pkgdir = ROOT / "packages" / a.pkg
    raw = ROOT / "build/test_audit/raw" / a.pkg
    out = ROOT / "build/test_audit/cov" / a.pkg; out.mkdir(parents=True, exist_ok=True)
    per = timings(raw / "run.jsonl", pkgdir)
    jobs = []
    if a.pkg == "server":
        for p in (raw / "cov").rglob("*.vm.json"):
            rel = str(p.relative_to(raw / "cov")).removesuffix(".vm.json")
            jobs.append((rel, p))
        with ThreadPoolExecutor(a.jobs) as ex:
            res = list(ex.map(lambda j: (j[0], server_cov(j[1], pkgdir)), jobs))
    else:
        res = []
        for p in (raw / "cov").glob("*.json"):
            rel = p.name.removesuffix(".json").replace("__", "/")
            rel = rel.split("/packages/client/", 1)[-1]
            d = json.loads(p.read_text()); cov = {}
            for k, v in d.items():
                nk = norm_key(k)
                if nk and not GEN.search(nk): cov[nk] = v
            res.append((rel, cov))
    for rel, cov in res:
        tests = per.get(rel, [])
        ok = bool(tests) and all(t["result"] == "success" for t in tests)
        (out / (rel.replace("/", "__") + ".json")).write_text(json.dumps(dict(file=rel, ok=ok, tests=tests, covered=cov)))
    print(f"{a.pkg}: {len(res)} files ingested, {sum(len(v) for v in per.values())} tests timed")


if __name__ == "__main__":
    main()
