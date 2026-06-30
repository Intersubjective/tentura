import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/sentry/report_sentry_message.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';

enum ScreenLoadErrorKind {
  network,
  session,
  permissions,
  server,
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
}) {
  final buffer = StringBuffer()
    ..writeln('[$label] load failed (ref ${details.supportRef})')
    ..writeln('kind=${details.kind.name}')
    ..writeln('title=${details.title}')
    ..writeln('message=${details.message}');
  if (details.detail != null && details.detail!.isNotEmpty) {
    buffer.writeln('detail=${details.detail}');
  }
  buffer.write('error=$error');
  final message = buffer.toString();
  GetIt.I<Logger>().warning(message);
  reportSentryMessage(message);
}

ScreenLoadErrorKind _classifyLoadError(Object error) {
  if (error is AuthSessionLostException ||
      error is SessionAuthRejectedException) {
    return ScreenLoadErrorKind.session;
  }
  if (error is ConnectionUplinkException || error is TimeoutException) {
    return ScreenLoadErrorKind.network;
  }
  if (error is ServerStatusException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return ScreenLoadErrorKind.session;
    }
    if (error.statusCode == 404) {
      return ScreenLoadErrorKind.permissions;
    }
    return ScreenLoadErrorKind.server;
  }
  if (error is RemoteApiException) {
    final message = error.message.toLowerCase();
    if (_looksLikePermissionFailure(message)) {
      return ScreenLoadErrorKind.permissions;
    }
    return ScreenLoadErrorKind.server;
  }
  if (error is ServerException) {
    return ScreenLoadErrorKind.server;
  }
  return ScreenLoadErrorKind.unknown;
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
  ScreenLoadErrorKind.session => l10n.screenLoadErrorSessionTitle,
  ScreenLoadErrorKind.permissions => l10n.screenLoadErrorPermissionsTitle,
  ScreenLoadErrorKind.server => l10n.screenLoadErrorServerTitle,
  ScreenLoadErrorKind.unknown => l10n.screenLoadErrorUnknownTitle,
};

String _messageFor(ScreenLoadErrorKind kind, Object error, L10n l10n) {
  if (error is Localizable) {
    return error.toL10n(l10n.localeName);
  }
  return switch (kind) {
    ScreenLoadErrorKind.network => l10n.screenLoadErrorNetworkBody,
    ScreenLoadErrorKind.session => l10n.screenLoadErrorSessionBody,
    ScreenLoadErrorKind.permissions => l10n.screenLoadErrorPermissionsBody,
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
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: _clipboardText(l10n),
                  ),
                ),
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
