import 'dart:io';
import 'dart:typed_data';

import 'package:mockito/mockito.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/private_avatar_repository.dart';
import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/env.dart';

// This entry point runs with a bounded Dart heap. The upload must reject
// impossible dimensions before trying to allocate the decoded image.
Future<void> main() async {
  final bytes = await stdin.fold(
    BytesBuilder(copy: false),
    (buffer, chunk) => buffer..add(chunk),
  );
  final repository = PrivateAvatarRepository(
    _Database(),
    _OwnerGraph(),
    _Storage(),
    _Quota(),
    _Environment(),
  );
  try {
    await repository.put(
      ownerId: 'owner',
      subject: const PersonSubject.user('subject'),
      bytes: Stream.value(bytes.takeBytes()),
    );
    stderr.writeln('Oversized avatar upload returned successfully');
    exitCode = 1;
  } on IdWrongException catch (error) {
    stdout.writeln(error.description);
  }
}

class _Database extends Mock implements TenturaDb {}

class _OwnerGraph extends Mock implements OwnerGraphTransactionPort {}

class _Storage extends Mock implements RemoteStoragePort {}

class _Quota extends Mock implements UploadQuotaRepositoryPort {}

class _Environment extends Mock implements Env {}
