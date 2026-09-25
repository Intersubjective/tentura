import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// tentura-9f0 landing gate acceptance (trial merge tentura-rsm)

/// Alloy tentura-9f0 landing gate — same ten paths as the bead acceptance command.
const kRsmAcceptanceTestPaths = [
  'test/features/beacon_threads/beacon_room_message_actions_sheet_test.dart',
  'test/features/beacon_threads/chat_read_receipts_fpi_landing_check_test.dart',
  'test/features/beacon_threads/chat_read_receipts_n59_landing_check_test.dart',
  'test/data/service/remote_api_client/direct_operation_routing_test.dart',
  'test/design_system/tentura_avatar_stack_test.dart',
  'test/design_system/tentura_tokens_avatar_size_small_test.dart',
  'test/features/beacon_threads/room_message_trailing_meta_layout_test.dart',
  'test/features/beacon_threads/room_cubit_unread_test.dart',
  'test/features/beacon_threads/beacon_threads_case_test.dart',
  'test/features/beacon_threads/room_message_reply_quote_landing_check_test.dart',
];

const _clientPackageRootSegments = ['packages', 'client'];

File _clientFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Client file not found: $relativePath');
}

File _repoContractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Realtime entity contract manifest not found');
}

List<String> _contractTestPaths(Map<String, dynamic> contract) {
  return (contract['contractTests']! as List).cast<String>();
}

void main() {
  group('trial merge landing check (tentura-9f0)', () {
    test('rsm acceptance bundle lists exactly ten client test paths', () {
      expect(
        kRsmAcceptanceTestPaths,
        hasLength(10),
        reason: 'bead tentura-9f0 acceptance command must stay in sync',
      );
    });

    test('rsm acceptance test files declare tentura-9f0 landing gate marker', () {
      for (final path in kRsmAcceptanceTestPaths) {
        final file = _clientFile(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains('tentura-9f0'),
          reason:
              '$path must tag the rsm landing gate for Alloy trial-merge tracking',
        );
      }
    });

    test('realtime contractTests registers the rsm landing check harness', () {
      final contract =
          jsonDecode(_repoContractFile().readAsStringSync())
              as Map<String, dynamic>;
      final contractTests = _contractTestPaths(contract);
      expect(
        contractTests,
        contains(
          'packages/client/test/features/beacon_threads/tentura_rsm_landing_check_test.dart',
        ),
        reason:
            'rsm landing gate must be part of the realtime contract evidence set',
      );
    });

    test('realtime contractTests registers every rsm acceptance path', () {
      final contract =
          jsonDecode(_repoContractFile().readAsStringSync())
              as Map<String, dynamic>;
      final contractTests = _contractTestPaths(contract);
      for (final relative in kRsmAcceptanceTestPaths) {
        final repoRelative = [..._clientPackageRootSegments, relative].join('/');
        expect(
          contractTests,
          contains(repoRelative),
          reason:
              'contractTests must list $repoRelative for the rsm landing gate',
        );
      }
    });
  });
}
