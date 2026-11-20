"""Run the real server analyzer gate with a stalled telemetry connection."""

from contextlib import ExitStack
from datetime import date
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[1]
TCP_SOCKETS = Path("/proc/net/tcp")


def observe_pending_connection(port, finished, observed):
    # Linux exposes outbound TCP connections in SYN_SENT (02). The private
    # proxy port distinguishes the analyzer's connection from other activity.
    loopback = int.from_bytes(socket.inet_aton("127.0.0.1"), sys.byteorder)
    destination = f"{loopback:08X}:{port:04X}"
    while not finished.is_set():
        for row in TCP_SOCKETS.read_text().splitlines()[1:]:
            _, _, remote, state, *_ = row.split()
            if remote == destination and state == "02":
                observed.set()
                return
        finished.wait(0.01)


@unittest.skipUnless(sys.platform == "linux", "requires Linux TCP backlog semantics")
class ServerAnalysisWithUnreachableTelemetryTest(unittest.TestCase):
    def test_server_analysis_completes_when_telemetry_cannot_connect(self):
        with (
            tempfile.TemporaryDirectory() as scratch,
            socket.socket() as proxy,
            ExitStack() as proxy_connections,
        ):
            pub_hosted_url = os.environ.get("PUB_HOSTED_URL", "https://pub.dev")
            pub_host = urlparse(pub_hosted_url).hostname or "pub.dev"
            telemetry = Path(scratch) / ".dart-tool"
            telemetry.mkdir()
            (telemetry / "dart-flutter-telemetry.config").write_text(
                f"reporting=1\ndart-tool={date.today()},1\n"
            )

            # Keep the loopback proxy's accept queue full and verify that a
            # fresh connection stalls. An immediate refusal would complete
            # before shutdown could cancel the in-flight analytics send.
            proxy.bind(("127.0.0.1", 0))
            proxy.listen(0)
            address = proxy.getsockname()
            proxy_connections.enter_context(socket.create_connection(address, timeout=2))
            for _ in range(8):
                try:
                    connection = socket.create_connection(address, timeout=0.2)
                except TimeoutError:
                    break
                proxy_connections.enter_context(connection)
            else:
                self.fail("Could not saturate the loopback proxy accept queue")

            finished = threading.Event()
            observed = threading.Event()
            observer = threading.Thread(
                target=observe_pending_connection,
                args=(address[1], finished, observed),
            )
            observer.start()
            try:
                # This is the server analyzer invocation in
                # analyzer_issue_budget_toolchain_integration_test.dart.
                result = subprocess.run(
                    ["bash", "scripts/check-analyze-baseline.sh", "packages/server"],
                    cwd=REPO_ROOT,
                    env={
                        "HOME": scratch,
                        "PATH": os.environ["PATH"],
                        "PUB_CACHE": os.environ.get(
                            "PUB_CACHE", str(Path.home() / ".pub-cache")
                        ),
                        "PUB_HOSTED_URL": pub_hosted_url,
                        "TMPDIR": scratch,
                        "ANALYZER_STATE_LOCATION_OVERRIDE": os.environ.get(
                            "ANALYZER_STATE_LOCATION_OVERRIDE",
                            str(Path(scratch) / "analyzer"),
                        ),
                        "DASH__TOOL": "dart-tool",
                        "https_proxy": f"http://127.0.0.1:{address[1]}",
                        # Leave analyzer plugin dependency resolution working.
                        "no_proxy": f"{pub_host},pub.dartlang.org,storage.googleapis.com",
                    },
                    capture_output=True,
                    text=True,
                    timeout=240,
                )
            finally:
                finished.set()
                observer.join()

            output = result.stdout + result.stderr
            self.assertTrue(observed.is_set(), f"No connection to the proxy.\n{output}")
            event_log = telemetry / "dart-flutter-telemetry.log"
            self.assertTrue(event_log.is_file(), f"No SDK telemetry log.\n{output}")
            events = [
                event["name"]
                for line in event_log.read_text().splitlines()
                for event in json.loads(line)["events"]
            ]
            self.assertIn("memory_info", events, output)
            self.assertNotRegex(
                output,
                r"(?i)Unhandled exception:|SocketException|"
                r"analysis server (?:crashed|shut down unexpectedly)",
            )
            self.assertEqual(result.returncode, 0, output)
            self.assertRegex(
                output,
                r"(?m)^check-analyze-baseline: packages/server OK \(\d+ <= \d+\)$",
            )


if __name__ == "__main__":
    unittest.main()
