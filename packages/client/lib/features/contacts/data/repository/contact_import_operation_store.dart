import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom_import.dart';
import 'package:uuid/uuid.dart';

import 'contact_import_lock.dart'
    if (dart.library.js_interop) 'contact_import_lock_web.dart';

/// Keeps an opaque server replay ID for a submission until its work finishes.
/// The lookup digest stays on this device. Neither the file nor its rows are
/// stored here, and the digest is never sent to the server.
final class ContactImportOperationStore {
  ContactImportOperationStore(String accountId) : _accountId = accountId;

  final String _accountId;

  String _key(List<PhantomImportContact> rows, bool keepContacts) {
    final input = jsonEncode([
      _accountId,
      keepContacts,
      for (final row in rows) [row.name, row.email, row.phone],
    ]);
    return 'contact_import:${sha256.convert(utf8.encode(input))}';
  }

  Future<T> run<T>(
    List<PhantomImportContact> rows,
    bool keepContacts,
    Future<T> Function(String operationId) import,
  ) {
    final key = _key(rows, keepContacts);
    return withContactImportLock(key, () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final pending = preferences.getString(key);
      final id = pending ?? const Uuid().v4();
      if (pending == null && !await preferences.setString(key, id)) {
        throw const UnknownException();
      }
      final result = await import(id);
      await preferences.remove(key);
      return result;
    });
  }
}
