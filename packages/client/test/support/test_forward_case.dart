import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../features/auth/auth_test_helpers.dart';
import '../features/block/support/controllable_block_case.dart';
import '../features/contacts/contacts_case_test.dart';
import 'test_realtime_sync.dart';

ForwardCase buildTestForwardCase(ForwardRepository repository) {
  final store = ContactNameStore();
  final realtime = buildTestRealtimeSync();
  final authLocal = EmptyAuthLocal();
  final contacts = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  addTearDown(() async {
    await contacts.dispose();
    await realtime.port.dispose();
    await store.dispose();
  });
  return ForwardCase(
    repository,
    authLocal,
    _UnusedFactCards(),
    _UnusedProfiles(),
    contacts,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
}

class _UnusedFactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedProfiles implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
