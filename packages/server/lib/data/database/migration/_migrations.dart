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
part 'm0011.dart';
part 'm0012.dart';
part 'm0013.dart';
part 'm0014.dart';
part 'm0015.dart';
part 'm0016.dart';
part 'm0017.dart';
part 'm0018.dart';
part 'm0019.dart';
part 'm0020.dart';
part 'm0021.dart';

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
        m0011,
        m0012,
        m0013,
        m0014,
        m0015,
        m0016,
        m0017,
        m0018,
        m0019,
        m0020,
        m0021,
      ]),
    );
