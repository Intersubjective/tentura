# web_socket_client (Tentura patch)

Vendored from [felangel/web_socket_client](https://github.com/felangel/web_socket_client) 0.2.1.

Patches vs upstream:
1. HTML `connect()` Completer race (`isCompleted` guards) — [PR #87](https://github.com/felangel/web_socket_client/pull/87)
2. Channel stream `onError` → reconnect; catch `Object` not only `Exception` so `StateError` cannot escape unhandled

Remove `packages/web_socket_client` and the `web_socket_client` entry in
`pubspec_overrides.yaml` when [PR #87](https://github.com/felangel/web_socket_client/pull/87)
is merged+released **and** upstream also covers patch (2).
