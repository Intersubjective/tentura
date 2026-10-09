# Frozen pre-U37 layout oracle

These immutable, byte-for-byte source snapshots come from revision
`5b8493621d3934eca8059b23197a01029123d952`. They preserve the independent geometry oracle
for the resumable `LayoutJob` tests without requiring Git history or network
access in shallow CI checkouts. Do not update them alongside production changes;
no deterministic geometry difference from this revision is approved.

| Fixture | Original path | SHA-256 |
| --- | --- | --- |
| `constellation_layout.dart.txt` | `packages/client/lib/features/constellation/domain/constellation_layout.dart` | `af8d947b657c3d4a33237481ade32d305909dfecd4a5f6b8803ddb23b94a33df` |
| `radial_hop_positions.dart.txt` | `packages/client/lib/features/graph/domain/layout/radial_hop_positions.dart` | `6e2c3e168714022e59fb6784068c6b752926799ba515e5a7a55e275a0eaaa2d4` |

The `.dart.txt` extension keeps these historical sources out of normal Dart
analysis and formatting. `existing_layout_fixture_replay.dart` copies them into
temporary Dart libraries and rewrites only imports: the radial placement import
uses the frozen radial source, and unchanged composition, constants and geometry
imports use the live package. Original fixture assertions and the job-versus-
legacy geometry comparison remain intact.
