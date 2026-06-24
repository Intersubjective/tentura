import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// ExceptionBase codes that indicate an internal/unexpected server fault.
const _internalFaultCodeNumbers = {
  1000, // GeneralExceptionCode.unspecifiedException
  1100, // AuthExceptionCode.unspecifiedException
  1200, // UserExceptionCode.unspecifiedException
  1300, // BeaconExceptionCode.unspecifiedException
  1400, // EvaluationExceptionCode.unspecified
};

bool isInternalFaultException(ExceptionBase exception) {
  return _internalFaultCodeNumbers.contains(exception.code.codeNumber);
}
