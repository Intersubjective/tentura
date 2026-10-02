import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';

/// Wire code of the "operation needs a Request, got a Post" rejection
/// (`BeaconExceptionCode.beaconNotRequest`, 1300 + index 21).
const kBeaconNotRequestWireCode = 1321;

/// Matches the rejection a Request-only guard raises for a Post.
///
/// Matched by wire code so a guard test reports an unrejected call as a failed
/// assertion rather than as a missing symbol.
final Matcher throwsBeaconNotRequest = throwsA(isBeaconNotRequest);

/// Matcher form of [throwsBeaconNotRequest], for use on a caught error.
final Matcher isBeaconNotRequest = isA<ExceptionBase>().having(
  (e) => e.code.codeNumber,
  'wire code',
  kBeaconNotRequestWireCode,
);
