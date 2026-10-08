# Analyzer plugin dependency setup failure

`stderr.txt` is captured stderr from the real Dart 3.13.0 analyzer CLI, not a
reconstructed error message. Only the temporary directory prefix was normalized
to `/tmp/analyzer-plugin-setup`.

The capture used a minimal Dart package with a local `tentura_lints` entry under
`plugins:` in `analysis_options.yaml`, an empty private `PUB_CACHE`, and an
isolated analysis-server cache supplied through its `--cache` option. The
analyzer's generated plugin package attempted `dart pub upgrade`; resolving
`analysis_server_plugin` failed with a socket error fetching from pub.dev.
The real server emitted `server.pluginError`, and `dart analyze
--no-fatal-warnings` routed its message and stack trace to stderr.

This SDK returned exit 4 during capture. The regression harness deliberately
replays the captured failure signal with analyzer exit 0 and a clean summary:
the acceptance criterion requires the gate to reject failed initialization even
when the analyzer reports success. The tests do not require the gate to retain
the captured wording or stack trace. Replay also avoids relying on network
availability, plugin cache state, or a particular installed SDK in CI.
