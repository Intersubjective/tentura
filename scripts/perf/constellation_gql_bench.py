#!/usr/bin/env python3
"""Constellation GraphQL latency/throughput bench against a local Tentura server.

Usage:
  constellation_gql_bench.py latency  --email <qa-email> [--peer <visible peer id>] [-n 20]
  constellation_gql_bench.py load     --email <qa-email> --projection FULL|ANCHORS

Logs in through the QA test-login endpoint (Caddy at https://dev.lvh.me:9443), then
calls the V2 API directly on 127.0.0.1:2080. The latency mode moves an anchor on
--peer (a person the viewer can see) and deletes it again afterwards.
See docs/plans/issue-235-constellation-interactive-measurements.md.
"""
import argparse, concurrent.futures as cf, http.cookiejar, json, ssl, statistics, sys, time, urllib.request

CADDY = "https://dev.lvh.me:9443"
API = "http://127.0.0.1:2080/api/v2/graphql"
IMG = "image { id hash height width }"
REQ = ("id authorId title status needs primaryNeedSlug startAt endAt addressLabel hasCoordinates isMine "
       "viewerHasActiveHelpOffer viewerIsRoomParticipant viewerHasForwardEdge helpOfferCount coverSource "
       "coverThumb { id hash height width }")
PROJ = (f"anchorProjection {{ revision anchors {{ targetKind targetId xUnits yUnits coordinateSpaceVersion revision placedAt }} "
        f"pinnedPeers {{ id displayName handle {IMG} }} pinnedRequests {{ {REQ} }} supportPeers {{ id displayName handle {IMG} }} "
        f"supportEdges {{ src dst tier }} serverFilteredBeaconIds serverFilteredBeaconCount }}")


def field(projection):
    return (f"query {{ constellationField(showClosed:false, participatedOnly:false, projection:{projection}) {{ "
            f"loadedAt context peersCapped requestsCapped peers {{ id displayName handle {IMG} }} edges {{ src dst tier }} "
            f"requests {{ {REQ} }} posts {{ id authorId lastActivityAt rootExcerpt isPinned hiddenReachCount }} "
            f"memberWebs {{ beaconId personId state }} {PROJ} }} }}")


def login(email, base):
    """QA test-login, then exchange the session cookie for a JWT. The cookie is
    carried by hand so this also works against the plain-HTTP server port."""
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
    resp = opener.open(urllib.request.Request(f"{base}/api/v2/auth/email/test-login",
                                              json.dumps({"email": email}).encode(),
                                              {"Content-Type": "application/json"}))
    cookies = "; ".join(c.split(";", 1)[0] for c in resp.headers.get_all("Set-Cookie") or [])
    tok = json.load(opener.open(urllib.request.Request(f"{base}/api/v2/session/access-token", b"",
                                                       {"Cookie": cookies}, method="POST")))
    return tok["access_token"]


class Client:
    def __init__(self, jwt):
        self.jwt = jwt

    def call(self, query, variables=None):
        body = json.dumps({"query": query, "variables": variables or {}}).encode()
        req = urllib.request.Request(API, body, {"Content-Type": "application/json", "Authorization": "Bearer " + self.jwt})
        t = time.perf_counter(); data = urllib.request.urlopen(req).read(); dt = (time.perf_counter() - t) * 1000
        j = json.loads(data)
        if j.get("errors"):
            sys.exit("GraphQL error: " + json.dumps(j["errors"])[:300])
        return dt, j, len(data)


def summary(name, xs):
    xs = sorted(xs); n = len(xs)
    print(f"{name:10s} n={n} p50={statistics.median(xs):8.1f} ms p95={xs[max(0, int(0.95 * n) - 1)]:8.1f} ms "
          f"min={xs[0]:7.1f} max={xs[-1]:7.1f}")


def latency(c, peer, n):
    _, j, size = c.call(field("FULL")); f = j["data"]["constellationField"]
    print(f"FULL payload {size} bytes; peers {len(f['peers'])} requests {len(f['requests'])} edges {len(f['edges'])}")
    for p in ("FULL", "ANCHORS"):
        c.call(field(p)); summary(p, [c.call(field(p))[0] for _ in range(n)])
    if peer:
        up = ("mutation($x:Float!,$y:Float!){ constellationAnchorUpsert(targetKind:PERSON,targetId:\"%s\","
              "xUnits:$x,yUnits:$y,coordinateSpaceVersion:1){ revision } }" % peer)
        summary("UPSERT", [c.call(up, {"x": 1.0 + (i % 5) * 0.1, "y": 2.0})[0] for i in range(n)])
        c.call("mutation{ constellationAnchorDelete(targetKind:PERSON,targetId:\"%s\"){ revision } }" % peer)
        print("test anchor deleted")


def load(c, projection):
    q = field(projection)
    for conc in (1, 8, 32):
        n = max(60, conc * 10); t = time.perf_counter()
        with cf.ThreadPoolExecutor(conc) as ex:
            xs = sorted(ex.map(lambda _: c.call(q)[0], range(n)))
        el = time.perf_counter() - t
        print(f"{projection} conc={conc:2d} n={n} throughput={n / el:6.1f} req/s "
              f"p50={statistics.median(xs):7.1f} ms p95={xs[int(.95 * n) - 1]:7.1f} ms")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["latency", "load"])
    ap.add_argument("--email", required=True)
    ap.add_argument("--peer")
    ap.add_argument("--projection", default="FULL")
    ap.add_argument("-n", type=int, default=20)
    ap.add_argument("--base", default=CADDY, help="login base URL (default Caddy); use http://127.0.0.1:2080 without Caddy")
    a = ap.parse_args()
    client = Client(login(a.email, a.base))
    latency(client, a.peer, a.n) if a.mode == "latency" else load(client, a.projection)
