// MainDbScopeAdmission moved to `data/database/main_db_scope_admission.dart`;
// this path stays for the constellation DB scheduler and its load harness,
// which still import it from here.
// TODO(desloppify): remove once lib/data/service/constellation_db_scheduler.dart
// and test/perf/constellation_d8_load_harness.dart import
// data/database/main_db_scope_admission.dart; tracked in the deferred list of
// #1173 (constellation files are out of scope for the desloppify PRs).
export '../database/main_db_scope_admission.dart';
