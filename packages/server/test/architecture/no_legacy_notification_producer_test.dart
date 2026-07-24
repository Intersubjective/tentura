import 'dart:io';

import 'package:test/test.dart';

const _beaconNotificationPortPath =
    'lib/domain/port/beacon_notification_port.dart';
const _notificationOutboxPortPath =
    'lib/domain/port/notification_outbox_repository_port.dart';
const _attentionDispatchRepositoryPath =
    'lib/data/repository/attention_dispatch_repository.dart';

final _retiredSymbol = RegExp(
  r'\b(?:BeaconRoomNotificationPort|InviteAcceptedNotificationPort)\b',
);
final _methodNamedDispatch = RegExp(r'\bdispatch\s*\(');
final _methodNamedEnqueue = RegExp(r'\benqueue\s*\(');
final _typedOutboxVariable = RegExp(
  r'\bNotificationOutboxRepositoryPort\s*\??\s+([A-Za-z_]\w*)\b',
);
final _outboxInsert = RegExp(
  r'\bINSERT\s+INTO\s+(?:public\s*\.\s*)?notification_outbox\b',
  caseSensitive: false,
);

void main() {
  test(
    'production code does not reintroduce retired notification producers',
    () {
      expect(_findViolations(_productionSources()), isEmpty);
    },
  );

  test('allows unrelated dispatch methods', () {
    final violations = _findViolations({
      'lib/data/service/task_dispatch_service.dart': '''
class TaskDispatchService {
  Future<void> dispatch() async {}
}
''',
      _beaconNotificationPortPath: '''
abstract class BeaconNotificationPort {
  Future<void> handOffChannels(List<Object> decisions);
}
''',
      _notificationOutboxPortPath: '''
abstract interface class NotificationOutboxRepositoryPort {
  Future<void> markEmailed(List<String> ids);
}
''',
      'lib/data/service/unrelated_queue.dart': '''
Future<void> queueWork(
  NotificationOutboxRepositoryPort outbox,
  TaskQueue queue,
) async {
  await outbox.markEmailed(const []);
  await queue.enqueue(Object());
}
''',
      _attentionDispatchRepositoryPath: '''
await database.customStatement(
  'INSERT INTO public.notification_outbox (id) VALUES (1)',
);
''',
    });

    expect(violations, isEmpty);
  });

  test('detects retired APIs despite whitespace and declaration variations', () {
    final violations = _findViolations({
      _beaconNotificationPortPath: '''
abstract interface class BeaconNotificationPort {
  Future<void>
  dispatch (
    Object value,
  );
}
''',
      _notificationOutboxPortPath: '''
abstract class NotificationOutboxRepositoryPort {
  Future<void>
  enqueue (
    Object item,
  );
}
''',
      'lib/domain/port/legacy.dart':
          'abstract class BeaconRoomNotificationPort {}',
      'lib/data/service/legacy_outbox_writer.dart': '''
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';

Future<void> write(NotificationOutboxRepositoryPort outbox) =>
    outbox.enqueue(Object());

await database.customStatement(
  'INSERT INTO notification_outbox (id) VALUES (1)',
);
''',
    });

    expect(
      violations,
      contains('$_beaconNotificationPortPath declares dispatch'),
    );
    expect(
      violations,
      contains('$_notificationOutboxPortPath declares enqueue'),
    );
    expect(
      violations,
      contains(
        'lib/domain/port/legacy.dart references retired notification producer',
      ),
    );
    expect(
      violations,
      contains(
        'lib/data/service/legacy_outbox_writer.dart calls '
        'NotificationOutboxRepositoryPort.enqueue',
      ),
    );
    expect(
      violations,
      contains(
        'lib/data/service/legacy_outbox_writer.dart writes notification_outbox '
        'outside AttentionDispatchRepository',
      ),
    );
  });
}

Map<String, String> _productionSources() => {
  for (final source
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')))
    source.path: source.readAsStringSync(),
};

List<String> _findViolations(Map<String, String> sources) {
  final violations = <String>[];

  for (final entry in sources.entries) {
    final code = _withoutComments(entry.value);
    if (_retiredSymbol.hasMatch(code)) {
      violations.add('${entry.key} references retired notification producer');
    }

    if (entry.key != _attentionDispatchRepositoryPath &&
        _outboxInsert.hasMatch(code)) {
      violations.add(
        '${entry.key} writes notification_outbox outside AttentionDispatchRepository',
      );
    }

    if (_callsOutboxEnqueue(code)) {
      violations.add(
        '${entry.key} calls NotificationOutboxRepositoryPort.enqueue',
      );
    }
  }

  final beaconPort = sources[_beaconNotificationPortPath];
  if (beaconPort != null &&
      _methodNamedDispatch.hasMatch(_withoutComments(beaconPort))) {
    violations.add('$_beaconNotificationPortPath declares dispatch');
  }

  final outboxPort = sources[_notificationOutboxPortPath];
  if (outboxPort != null &&
      _methodNamedEnqueue.hasMatch(_withoutComments(outboxPort))) {
    violations.add('$_notificationOutboxPortPath declares enqueue');
  }

  return violations;
}

bool _callsOutboxEnqueue(String code) {
  for (final declaration in _typedOutboxVariable.allMatches(code)) {
    final variable = declaration.group(1)!;
    final enqueueCall = RegExp(
      '\\b${RegExp.escape(variable)}\\s*\\.\\s*enqueue\\s*\\(',
    );
    if (enqueueCall.hasMatch(code)) return true;
  }
  return false;
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*$', multiLine: true), '');
