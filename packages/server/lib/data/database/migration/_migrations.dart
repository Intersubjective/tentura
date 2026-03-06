import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:postgres/postgres.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';

part 'm0001.dart';
part 'm0002.dart';
part 'm0003.dart';
part 'm0004.dart';
part 'm0005.dart';
part 'm0006.dart';
part 'm0007.dart';
part 'm0008.dart';
part 'm0009.dart';
part 'm0010.dart';

Future<void> migrateDbSchema(Connection connection) =>
    Database(PostgreSQLGateway(connection)).upgrade(
      InMemory([
        m0001,
        m0002,
        m0003,
        m0004,
        m0005,
        m0006,
        m0007,
        m0008,
        m0009,
        m0010,
      ]),
    );
