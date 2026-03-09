import 'package:tentura_server/env.dart';
import 'package:tentura_server/app/di.dart';
// import 'package:tentura_server/data/database/tentura_db.dart';
// import 'package:tentura_server/domain/use_case/task_worker_case.dart';

Future<void> calculateBlurHashes() async {
  final getIt = await configureDependencies(Env.prod());
  // final database = getIt<TenturaDb>();

  await getIt.reset();
}
