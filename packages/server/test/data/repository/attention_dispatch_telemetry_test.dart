import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

void main() {
  test('receipt_created telemetry uses marker and omits recipient ids', () {
    final recipientId = 'U-secret-recipient-42';
    final line = AttentionDispatchRepository.formatReceiptCreatedTelemetry(
      eventType: AttentionEventType.commitmentAccepted,
      recipientCount: 2,
      occurrenceAt: DateTime.utc(2026, 8, 5, 12, 34, 56),
    );

    expect(line, contains('attention_event=receipt_created'));
    expect(line, contains('event_type=commitmentAccepted'));
    expect(line, contains('recipients=2'));
    expect(line, contains('occurrence_at=2026-08-05T12:34:56.000Z'));
    expect(line, isNot(contains(recipientId)));
    expect(line, isNot(contains('title=')));
    expect(line, isNot(contains('body=')));
  });

  test('receipt_created telemetry is emitted through the logger', () {
    final records = <LogRecord>[];
    final logger = Logger('attention-dispatch-telemetry-test')
      ..onRecord.listen(records.add);

    AttentionDispatchRepository.logReceiptCreatedTelemetry(
      logger: logger,
      eventType: AttentionEventType.coordinationChanged,
      recipientCount: 3,
      occurrenceAt: DateTime.utc(2026, 8, 5, 1),
    );

    expect(records, hasLength(1));
    expect(records.single.message, contains('attention_event=receipt_created'));
    expect(records.single.message, isNot(contains('U-')));
  });
}
