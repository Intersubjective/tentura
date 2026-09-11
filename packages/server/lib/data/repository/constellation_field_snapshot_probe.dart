import '../database/tentura_db.dart';

/// Optional hook for PostgreSQL snapshot isolation proofs in pg tests only.
Future<void> Function(TenturaDb db)? constellationFieldSnapshotOpenProbe;
