@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'attention_dismiss_sweep_pg_test.dart' as sweep;

// Repository-level verification uses this entry point. Run the existing
// Dismiss all suite, including its capture, apply, race and undo assertions.
Future<void> main() => sweep.main();
