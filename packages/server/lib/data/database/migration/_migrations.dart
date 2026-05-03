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
part 'm0022.dart';
part 'm0023.dart';
part 'm0024.dart';
part 'm0025.dart';
part 'm0026.dart';
part 'm0027.dart';
part 'm0028.dart';
part 'm0029.dart';
part 'm0030.dart';
part 'm0031.dart';
part 'm0032.dart';
part 'm0033.dart';
part 'm0034.dart';
part 'm0035.dart';
part 'm0036.dart';
part 'm0037.dart';
part 'm0038.dart';
part 'm0039.dart';
part 'm0040.dart';
part 'm0041.dart';
part 'm0042.dart';
part 'm0043.dart';
part 'm0044.dart';
part 'm0045.dart';
part 'm0046.dart';
part 'm0047.dart';
part 'm0048.dart';
part 'm0049.dart';
part 'm0050.dart';
part 'm0051.dart';
part 'm0052.dart';

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
        m0022,
        m0023,
        m0024,
        m0025,
        m0026,
        m0027,
        m0028,
        m0029,
        m0030,
        m0031,
        m0032,
        m0033,
        m0034,
        m0035,
        m0036,
        m0037,
        m0038,
        m0039,
        m0040,
        m0041,
        m0042,
        m0043,
        m0044,
        m0045,
        m0046,
        m0047,
        m0048,
        m0049,
        m0050,
        m0051,
        m0052,
      ]),
    );
