@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/room/attachment_filename.dart'
    show attachmentDisplayName, sanitizedAttachmentBaseName;
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../support/attachment_normalization_probe.dart';
import '../support/fake_beacon_hierarchy_repository.dart';
import '../support/fake_user_block_repository.dart';

const _userId = 'Uaaaaaaaaaaaa';

class _CapturingRoom extends Fake implements BeaconRoomRepositoryPort {}

class _AllowingQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

class _CapturingRemoteStorage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    return path;
  }
}

class _CapturingImages extends Fake implements ImageRepositoryPort {
  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async => 'Iaaaaaaaaaaaa';
}

class _CapturingTasks extends Fake implements TaskRepositoryPort {}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

BeaconRoomCase _sut({
  required _CapturingRoom room,
  required _CapturingRemoteStorage storage,
  ImageRepositoryPort? images,
}) => BeaconRoomCase(
  room,
  _FakeItems(),
  _FakeFactCards(),
  images ?? _CapturingImages(),
  _CapturingTasks(),
  storage,
  _FakePolling(),
  _AllowingQuota(),
  FakeUserBlockRepository(),
  PassThroughMutatingUnitOfWork(),
  FakeBeaconHierarchyRepository(),
  const ProductionDiscussionProductPolicy(),
  env: Env(environment: Environment.test),
  logger: Logger('BeaconRoomAttachmentUploadTest'),
);

// Coverage: W25 = both public policies and a shared delegate; W27 = client mappings plus server-only extensions, real upload
// fallback, one evaluated shared table referenced by both consumer methods.
// Siblings: input = separators/whitespace/case/unknown/explicit MIME;
// surface = both filename APIs, picker and upload normalizer. PG covers an
// author attaching to an open discussion; the picker covers 375x667 with RU.
// Other roles/states, freshness and network timing are n/a: this extraction
// changes no access policy, synchronization or network behavior.
// Client picker behavior: client/test/ui/widget/picked_attachment_mime_test.dart.
// Real persistence path: domain/use_case/attachment_mime_persistence_pg_test.dart.
const _union = {
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  // Server-only extensions retain the previous server fallback.
  'gif': 'image/jpeg',
  'heic': 'image/jpeg',
  'heif': 'image/jpeg',
};

void main() {
  final root = Directory('../..').absolute.uri;
  final graph = AttachmentNormalizationGraph(root);

  test(
    'filename APIs share basename extraction and preserve separator and whitespace rules',
    () async {
      const inputs = [
        '/uploads/report final.pdf   ',
        r'C:\uploads\report final.pdf   ',
        'report final.pdf   ',
      ];
      for (final path in inputs) {
        expect(attachmentDisplayName(path), 'report final.pdf');
        expect(sanitizedAttachmentBaseName(path), 'report_final.pdf');
      }
      for (final path in ['', '  ', '/uploads/  ', r'C:\uploads\  ']) {
        expect(attachmentDisplayName(path), 'file');
        expect(sanitizedAttachmentBaseName(path), 'file');
      }
      expect(attachmentDisplayName('/uploads/Отчёт.pdf  '), 'Отчёт.pdf');
      expect(sanitizedAttachmentBaseName('/uploads/Отчёт.pdf  '), '_.pdf');
      final display = graph.reachable(
        'packages/server/lib/domain/room/attachment_filename.dart',
        'attachmentDisplayName',
      );
      final download = graph.reachable(
        'packages/server/lib/domain/room/attachment_filename.dart',
        'sanitizedAttachmentBaseName',
      );
      expect(
        await graph.evaluate(
          display.singleWhere(
            (definition) => definition.name == 'attachmentDisplayName',
          ),
          inputs: inputs,
        ),
        List.filled(inputs.length, 'report final.pdf'),
      );
      final shared = display
          .intersection(download)
          .where(
            (definition) => !definition.isVariable,
          )
          .toList();
      expect(
        shared,
        isNotEmpty,
        reason:
            'Both public APIs must delegate basename extraction to a common helper',
      );
      final basenameDelegates = <NormalizationDefinition>[];
      for (final helper in shared) {
        final values = await graph.evaluate(helper, inputs: inputs);
        // Trimming may belong to the helper or the two public policies. Only
        // basename extraction must be shared; do not prescribe that detail.
        if (values is List &&
            values.every(
              (value) => value is String && value.trim() == 'report final.pdf',
            )) {
          basenameDelegates.add(helper);
        }
      }
      expect(
        basenameDelegates,
        isNotEmpty,
        reason:
            'Both APIs must delegate basename extraction, regardless of visibility, forwarding wrappers, or where trimming occurs',
      );
    },
  );

  for (final extension in ['png', 'webp']) {
    test(
      'uploads without a declared MIME type infer image/$extension from the filename',
      () async {
        final sut = _sut(
          room: _CapturingRoom(),
          storage: _CapturingRemoteStorage(),
        );
        for (final suffix in [extension, extension.toUpperCase()]) {
          final result = await sut.prepareMessageAttachment(
            userId: _userId,
            bytes: Stream.value(
              Uint8List.fromList('no image signature'.codeUnits),
            ),
            uploadFilename: 'file.$suffix',
          );
          expect(result, isNotNull);
          expect(result!.mime, _union[extension], reason: suffix);
        }
      },
    );
  }

  test(
    'extension MIME fallback entries have a single owner across production libraries',
    () {
      final tables = graph.mimeTables(_union.keys.toSet());
      expect(
        tables,
        hasLength(1),
        reason:
            'Remove duplicate extension-to-MIME tables, including unused helpers: $tables',
      );
      expect(
        tables.single.uri.path.startsWith(root.resolve('lib/').path),
        isTrue,
      );
    },
  );

  test(
    'picker and upload fallback use one shared table containing the compatibility union',
    () async {
      // Verify the VM probe can read evaluated map entries before relying on it
      // to classify production owners. No implementation is copied or executed
      // by a test-side interpreter.
      expect(
        await graph.evaluate(
          graph.declaration(
            'packages/server/test/architecture/attachment_normalization_ownership_test.dart',
            '_union',
          ),
        ),
        _union,
      );
      final picker = graph.reachable(
        'packages/client/lib/ui/widget/pending_attachments.dart',
        'pickFileAttachments',
      );
      final server = graph.reachable(
        'packages/server/lib/domain/use_case/beacon_room_case.dart',
        '_normalizeAttachmentMime',
      );
      final common = picker
          .intersection(server)
          .where(
            (definition) =>
                definition.isVariable &&
                definition.uri.path.startsWith(root.resolve('lib/').path),
          );
      final tables = <NormalizationDefinition>[];
      for (final definition in common) {
        final value = await graph.evaluate(definition);
        if (value is Map && _union.keys.every(value.containsKey)) {
          tables.add(definition);
          for (final entry in _union.entries) {
            expect(
              value[entry.key],
              entry.value,
              reason: '${definition.name}[${entry.key}]',
            );
          }
        }
      }
      expect(
        tables,
        hasLength(1),
        reason:
            'Both consumer call graphs must reach exactly one actual root extension-to-MIME table, including client PNG/WebP and server GIF/HEIC/HEIF',
      );

      // Exercise the shared lookup function itself (including unknown and case
      // behavior), rather than reimplementing lookup in this test.
      final lookups = picker
          .intersection(server)
          .where(
            (definition) =>
                !definition.isVariable &&
                definition.uri.path.startsWith(root.resolve('lib/').path),
          );
      final lookupResults = <List<dynamic>>[];
      final extensions = [
        ..._union.keys,
        ..._union.keys.map((ext) => ext.toUpperCase()),
        'unknown',
        '',
      ];
      final expected = [
        ..._union.values,
        ..._union.values,
        'application/octet-stream',
        'application/octet-stream',
      ];
      for (final lookup in lookups) {
        final value = await graph.evaluate(lookup, inputs: extensions);
        if (value is List &&
            value.length == expected.length &&
            value.first == 'application/pdf') {
          expect(value, expected, reason: lookup.toString());
          lookupResults.add(value);
        }
      }
      expect(
        lookupResults,
        isNotEmpty,
        reason:
            'Both consumers must call the root MIME lookup, not merely import its library',
      );
      final sut = _sut(
        room: _CapturingRoom(),
        storage: _CapturingRemoteStorage(),
      );
      for (var i = 0; i < extensions.length; i++) {
        final ext = extensions[i];
        final result = await sut.prepareMessageAttachment(
          userId: _userId,
          bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
          uploadFilename: ext.isEmpty ? 'file' : 'file.$ext',
        );
        expect(result, isNotNull);
        expect(result!.mime, expected[i], reason: ext);
      }
      final explicit = await sut.prepareMessageAttachment(
        userId: _userId,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
        uploadFilename: 'file.pdf',
        uploadMimeType: ' application/custom ',
      );
      expect(explicit!.mime, 'application/custom');
    },
  );
}
