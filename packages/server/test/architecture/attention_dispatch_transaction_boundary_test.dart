import 'dart:io';

import 'package:test/test.dart';

/// U05c's verify found `UserBlockCase` calling `AttentionDispatchPort.record`
/// without going through [TransactionalAttentionCase]. It is safe only because
/// `block()` wraps the call in its own `MutatingUnitOfWorkPort.run`, and
/// because that path emits no obligations — a coincidence, not a guarantee.
///
/// This is the structural guard for it: a direct holder of the dispatch port
/// must also own a transaction boundary. It is a lint-like inventory test
/// rather than a runtime assertion on purpose — the defect class is "who holds
/// the port", which no runtime check can see (the U05c call site *is* inside an
/// ambient transaction and would pass one), and a throw on a real user path
/// would be worse than the coincidence it replaces.
void main() {
  /// Every `lib/` file that names the dispatch port, by repo-relative path.
  const declaredHolders = <String>{
    // The port declaration itself.
    'lib/domain/port/attention_dispatch_port.dart',
    // The implementation.
    'lib/data/repository/attention_dispatch_repository.dart',
    // The one sanctioned boundary: it wraps every record in a unit of work.
    'lib/domain/use_case/transactional_attention_case.dart',
    // Owns its own `MutatingUnitOfWorkPort.run`; cannot nest
    // `TransactionalAttentionCase.runAction` because the withdrawn offerer is
    // not the blocking actor and nested actor mismatch is a StateError.
    'lib/domain/use_case/user_block_case.dart',
  };

  test('direct dispatch-port holders are a declared, reviewed set', () {
    expect(
      _dispatchPortHolders(),
      declaredHolders,
      reason:
          'A new holder of AttentionDispatchPort bypasses '
          'TransactionalAttentionCase. Declare it here only with a transaction '
          'boundary of its own.',
    );
  });

  test('every direct holder owns a mutating transaction boundary', () {
    for (final path in _dispatchPortHolders()) {
      if (path == 'lib/domain/port/attention_dispatch_port.dart' ||
          path == 'lib/data/repository/attention_dispatch_repository.dart' ||
          path == 'lib/domain/use_case/transactional_attention_case.dart') {
        continue;
      }
      expect(
        _ownsTransactionBoundary(File(path).readAsStringSync()),
        isTrue,
        reason:
            '$path records attention without holding a MutatingUnitOfWorkPort, '
            'so its receipts can be written outside any transaction',
      );
    }
  });

  test('the boundary rule rejects a bare dispatch holder', () {
    const violating = '''
final class RogueCase {
  RogueCase(this._dispatch);
  final AttentionDispatchPort _dispatch;
  Future<void> run() => _dispatch.record(intent);
}
''';
    const compliant = '''
final class SafeCase {
  SafeCase(this._unitOfWork, this._dispatch);
  final MutatingUnitOfWorkPort _unitOfWork;
  final AttentionDispatchPort _dispatch;
  Future<void> run() =>
      _unitOfWork.run(action: () => _dispatch.record(intent));
}
''';
    expect(_ownsTransactionBoundary(violating), isFalse);
    expect(_ownsTransactionBoundary(compliant), isTrue);
  });
}

bool _ownsTransactionBoundary(String source) =>
    source.contains('MutatingUnitOfWorkPort');

Set<String> _dispatchPortHolders() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    // Generated DI wiring names every port; it is not a caller.
    .where((file) => !file.path.endsWith('di.config.dart'))
    .where((file) => file.readAsStringSync().contains('AttentionDispatchPort'))
    .map((file) => file.path)
    .toSet();
