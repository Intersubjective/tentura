import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

export 'package:tentura_server/domain/exception_codes.dart'
    show ClosureExceptionCode;

final class ClosureException extends ExceptionBase {
  const ClosureException._(this.closureCode, ExceptionCodes code, String d)
    : super(code: code, description: d);

  const ClosureException.notAuthor()
    : this._(
        ClosureExceptionCode.notAuthor,
        const ClosureExceptionCodes(ClosureExceptionCode.notAuthor),
        'notAuthor',
      );

  const ClosureException.notVoter()
    : this._(
        ClosureExceptionCode.notVoter,
        const ClosureExceptionCodes(ClosureExceptionCode.notVoter),
        'notVoter',
      );

  const ClosureException.notMember()
    : this._(
        ClosureExceptionCode.notMember,
        const ClosureExceptionCodes(ClosureExceptionCode.notMember),
        'notMember',
      );

  const ClosureException.staleEpoch()
    : this._(
        ClosureExceptionCode.staleEpoch,
        const ClosureExceptionCodes(ClosureExceptionCode.staleEpoch),
        'staleEpoch',
      );

  const ClosureException.wrongStatus()
    : this._(
        ClosureExceptionCode.wrongStatus,
        const ClosureExceptionCodes(ClosureExceptionCode.wrongStatus),
        'wrongStatus',
      );

  const ClosureException.reopenLimit()
    : this._(
        ClosureExceptionCode.reopenLimit,
        const ClosureExceptionCodes(ClosureExceptionCode.reopenLimit),
        'reopenLimit',
      );

  const ClosureException.extendLimit()
    : this._(
        ClosureExceptionCode.extendLimit,
        const ClosureExceptionCodes(ClosureExceptionCode.extendLimit),
        'extendLimit',
      );

  const ClosureException.notReady()
    : this._(
        ClosureExceptionCode.notReady,
        const ClosureExceptionCodes(ClosureExceptionCode.notReady),
        'notReady',
      );

  const ClosureException.invalidSplit()
    : this._(
        ClosureExceptionCode.invalidSplit,
        const ClosureExceptionCodes(ClosureExceptionCode.invalidSplit),
        'invalidSplit',
      );

  const ClosureException.splitTooLarge()
    : this._(
        ClosureExceptionCode.splitTooLarge,
        const ClosureExceptionCodes(ClosureExceptionCode.splitTooLarge),
        'splitTooLarge',
      );

  final ClosureExceptionCode closureCode;
}
