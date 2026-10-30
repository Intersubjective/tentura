import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/sentry/report_sentry_message.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/parallel_wait_failure.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';

enum ScreenLoadErrorKind {
  /// Offline, or the request timed out (including a timeout wrapped by a
  /// parallel desk read).
  network,

  /// The in-flight read was aborted. A retry of this kind is not a Sentry
  /// issue; the attempt that gives up is.
  cancelled,

  session,
  permissions,

  /// The server was unavailable (HTTP 5xx, 408, 429). A retry of this kind is
  /// not a Sentry issue; the attempt that gives up is.
  unavailable,

  /// The server answered with a GraphQL error.
  server,

  /// A parse, mapping, or other non-transient failure.
  unknown,
}

final class ScreenLoadErrorDetails {
  const ScreenLoadErrorDetails({
    required this.kind,
    required this.title,
    required this.message,
    required this.supportRef,
    this.detail,
  });

  final ScreenLoadErrorKind kind;
  final String title;
  final String message;
  final String supportRef;
  final String? detail;
}

ScreenLoadErrorDetails describeScreenLoadError({
  required Object error,
  required L10n l10n,
}) {
  final kind = _classifyLoadError(error);
  final detail = _errorDetail(error);
  final supportRef = _supportRefFor(error);
  return ScreenLoadErrorDetails(
    kind: kind,
    title: _titleFor(kind, l10n),
    message: _messageFor(kind, error, l10n),
    detail: detail,
    supportRef: supportRef,
  );
}

void logScreenLoadError({
  required String label,
  required Object error,
  required ScreenLoadErrorDetails details,
  bool willRetry = false,
}) {
  final buffer = StringBuffer()
    ..writeln('[$label] load failed (ref ${details.supportRef})')
    ..writeln('kind=${details.kind.name}')
    ..writeln('title=${details.title}')
    ..writeln('message=${details.message}');
  if (details.detail != null && details.detail!.isNotEmpty) {
    buffer.writeln('detail=${details.detail}');
  }
  // Only a transient attempt that is about to be retried. A GraphQL or parse
  // error never carries this, so it cannot hide behind the retry.
  if (willRetry && isTransientScreenLoadFailure(error)) {
    buffer.writeln('retrying=1');
  }
  buffer.write('error=$error');
  final message = buffer.toString();
  GetIt.I<Logger>().warning(message);
  reportSentryMessage(message);
}

/// Holds My Work's latest load failure and reports it once.
///
/// A transient failure (timeout, cancel, offline, server unavailable) is not
/// sent while the user can still retry. [observe] with a null error drops it
/// when the retry succeeds. [reportFinal] sends the failure still showing
/// when the screen goes away. A parse or GraphQL error is sent immediately,
/// and a later attempt in the same streak does not send another.
final class ScreenLoadReportGate {
  Object? _error;
  ScreenLoadErrorDetails? _details;
  String? _label;
  var _reported = false;

  void observe({
    required String label,
    required Object? error,
    ScreenLoadErrorDetails? details,
  }) {
    if (error == null) {
      _error = null;
      _details = null;
      _label = null;
      _reported = false;
      return;
    }
    if (identical(error, _error)) return;
    _error = error;
    _label = label;
    if (!isTransientScreenLoadFailure(error)) {
      _details = null;
      if (_reported) return;
      logScreenLoadError(label: label, error: error, details: details!);
      _reported = true;
      return;
    }
    _details = details;
  }

  void reportFinal() {
    final error = _error;
    final details = _details;
    final label = _label;
    if (error == null || details == null || label == null || _reported) {
      return;
    }
    if (!GetIt.I.isRegistered<Logger>()) return;
    logScreenLoadError(label: label, error: error, details: details);
    _reported = true;
    _details = null;
  }
}

/// Timeout, cancelled read, connectivity loss, or the server being unavailable.
/// A parse, mapping, or GraphQL error is not transient.
bool isTransientScreenLoadFailure(Object error) =>
    _isTransientKind(_classifyLoadError(error));

bool _isTransientKind(ScreenLoadErrorKind kind) => switch (kind) {
  ScreenLoadErrorKind.network ||
  ScreenLoadErrorKind.cancelled ||
  ScreenLoadErrorKind.unavailable => true,
  ScreenLoadErrorKind.session ||
  ScreenLoadErrorKind.permissions ||
  ScreenLoadErrorKind.server ||
  ScreenLoadErrorKind.unknown => false,
};

/// Pull a timeout or abort out of the wrappers a parallel desk read leaves
/// around it ([ParallelWaitError], [GraphQLException]). A sibling that is not
/// transient wins, so a mapping error is not reclassified as a timeout.
Object _unwrapLoadError(Object error) {
  if (error is GraphQLException) {
    final inner = error.error;
    if (inner != null && !identical(inner, error)) {
      return _unwrapLoadError(inner);
    }
  }
  final causes = parallelWaitCauses(error);
  if (causes != null && causes.isNotEmpty) {
    Object? firstTransient;
    for (final cause in causes) {
      final inner = _unwrapLoadError(cause);
      if (!_isTransientKind(_classifyFlat(inner))) {
        return inner;
      }
      firstTransient ??= inner;
    }
    return firstTransient ?? error;
  }
  return error;
}

ScreenLoadErrorKind _classifyLoadError(Object error) =>
    _classifyFlat(_unwrapLoadError(error));

ScreenLoadErrorKind _classifyFlat(Object error) {
  if (error is AuthSessionLostException ||
      error is SessionAuthRejectedException) {
    return ScreenLoadErrorKind.session;
  }
  if (error is ConnectionUplinkException ||
      error is RequestTimeoutException ||
      error is TimeoutException) {
    return ScreenLoadErrorKind.network;
  }
  if (error is http.RequestAbortedException ||
      error is GraphQLNoDataException) {
    return ScreenLoadErrorKind.cancelled;
  }
  if (error is ServerStatusException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return ScreenLoadErrorKind.session;
    }
    if (error.statusCode == 404) {
      return ScreenLoadErrorKind.permissions;
    }
    if (_isUnavailableStatus(error.statusCode)) {
      return ScreenLoadErrorKind.unavailable;
    }
    return ScreenLoadErrorKind.server;
  }
  if (error is RemoteApiRetryLaterException) {
    // The server's admission backoff outlived the read retries: still a
    // server-side condition, not an unknown failure.
    return ScreenLoadErrorKind.server;
  }
  if (error is RemoteApiException) {
    final message = error.message.toLowerCase();
    if (_looksLikePermissionFailure(message)) {
      return ScreenLoadErrorKind.permissions;
    }
    final status = _serverHttpStatus(error.message);
    if (status != null && _isUnavailableStatus(status)) {
      return ScreenLoadErrorKind.unavailable;
    }
    return ScreenLoadErrorKind.server;
  }
  if (error is ServerException) {
    return ScreenLoadErrorKind.server;
  }
  return ScreenLoadErrorKind.unknown;
}

/// HTTP 5xx, 408 and 429: the server did not produce a GraphQL answer.
bool _isUnavailableStatus(int status) =>
    status >= 500 || status == 408 || status == 429;

final _serverHttpStatusPattern = RegExp(r'^Server error \(HTTP (\d+)\)$');

int? _serverHttpStatus(String message) {
  final match = _serverHttpStatusPattern.firstMatch(message.trim());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

bool _looksLikePermissionFailure(String message) {
  const markers = [
    'permission',
    'not authorized',
    'unauthorized',
    'access denied',
    'forbidden',
    'not allowed',
  ];
  return markers.any(message.contains);
}

String? _errorDetail(Object error) {
  if (error is RemoteApiException) {
    final trimmed = error.message.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (error is ServerStatusException) {
    return 'HTTP ${error.statusCode}';
  }
  if (error is Localizable) {
    return error.toEn;
  }
  final raw = error.toString().trim();
  return raw.isEmpty ? null : raw;
}

String _supportRefFor(Object error) {
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch % 1000000;
  final typeHash = error.runtimeType.hashCode.abs() % 1000;
  return 'E${stamp.toString().padLeft(6, '0')}${typeHash.toString().padLeft(3, '0')}';
}

String _titleFor(ScreenLoadErrorKind kind, L10n l10n) => switch (kind) {
  ScreenLoadErrorKind.network => l10n.screenLoadErrorNetworkTitle,
  ScreenLoadErrorKind.cancelled => l10n.screenLoadErrorUnknownTitle,
  ScreenLoadErrorKind.session => l10n.screenLoadErrorSessionTitle,
  ScreenLoadErrorKind.permissions => l10n.screenLoadErrorPermissionsTitle,
  ScreenLoadErrorKind.unavailable => l10n.screenLoadErrorServerTitle,
  ScreenLoadErrorKind.server => l10n.screenLoadErrorServerTitle,
  ScreenLoadErrorKind.unknown => l10n.screenLoadErrorUnknownTitle,
};

String _messageFor(ScreenLoadErrorKind kind, Object error, L10n l10n) {
  if (error is Localizable) {
    return error.toL10n(l10n.localeName);
  }
  return switch (kind) {
    ScreenLoadErrorKind.network => l10n.screenLoadErrorNetworkBody,
    ScreenLoadErrorKind.cancelled => l10n.screenLoadErrorUnknownBody,
    ScreenLoadErrorKind.session => l10n.screenLoadErrorSessionBody,
    ScreenLoadErrorKind.permissions => l10n.screenLoadErrorPermissionsBody,
    ScreenLoadErrorKind.unavailable => l10n.screenLoadErrorServerBody,
    ScreenLoadErrorKind.server => l10n.screenLoadErrorServerBody,
    ScreenLoadErrorKind.unknown => l10n.screenLoadErrorUnknownBody,
  };
}

class ScreenLoadErrorPanel extends StatelessWidget {
  const ScreenLoadErrorPanel({
    required this.details,
    required this.onRetry,
    this.onSignInAgain,
    super.key,
  });

  final ScreenLoadErrorDetails details;
  final VoidCallback onRetry;
  final VoidCallback? onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final showSignIn =
        details.kind == ScreenLoadErrorKind.session && onSignInAgain != null;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tt.contentMaxWidth ?? 560,
        ),
        child: Padding(
          padding: tt.cardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: tt.iconSize * 2,
                color: scheme.error,
              ),
              SizedBox(height: tt.sectionGap),
              Text(
                details.title,
                style: TenturaText.title(scheme.onSurface),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tt.rowGap),
              Text(
                details.message,
                style: TenturaText.bodyMedium(scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (details.detail != null &&
                  details.detail != details.message) ...[
                SizedBox(height: tt.tightGap),
                Text(
                  details.detail!,
                  style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: tt.sectionGap),
              Text(
                l10n.screenLoadErrorSupportRef(details.supportRef),
                style: TenturaText.bodySmall(scheme.outline),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tt.sectionGap),
              FilledButton(
                onPressed: onRetry,
                child: Text(l10n.myWorkRetry),
              ),
              if (showSignIn) ...[
                SizedBox(height: tt.rowGap),
                TextButton(
                  onPressed: onSignInAgain,
                  child: Text(l10n.authSessionProblemFixAction),
                ),
              ],
              SizedBox(height: tt.tightGap),
              TextButton(
                onPressed: () {
                  unawaited(copyTextToClipboard(_clipboardText(l10n)));
                },
                child: Text(l10n.copyToClipboard),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _clipboardText(L10n l10n) {
    final buffer = StringBuffer()
      ..writeln(details.title)
      ..writeln(details.message);
    if (details.detail != null && details.detail!.isNotEmpty) {
      buffer.writeln(details.detail);
    }
    buffer.write(l10n.screenLoadErrorSupportRef(details.supportRef));
    return buffer.toString();
  }
}
