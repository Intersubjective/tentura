import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

DatabaseConnection Function() localDatabaseOpener(
  String name, {
  required Future<void> Function(QueryExecutor) restoreAccounts,
}) =>
    () => driftDatabase(
      name: name,
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    );
