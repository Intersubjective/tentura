import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebugErrorStore extends ChangeNotifier {
  DebugErrorStore._();

  static final DebugErrorStore instance = DebugErrorStore._();

  String? _lastError;

  String? get lastError => _lastError;

  void report(Object error, StackTrace stack, [String? details]) {
    final text = details ?? '$error\n\n$stack';
    _lastError = text;

    debugPrint('\n========== FLUTTER ERROR ==========\n$text\n===================================\n',
        wrapWidth: 1024);

    notifyListeners();
  }

  void clear() {
    _lastError = null;
    notifyListeners();
  }
}

void installDebugErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);

    DebugErrorStore.instance.report(
      details.exception,
      details.stack ?? StackTrace.current,
      details.toString(),
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DebugErrorStore.instance.report(error, stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    DebugErrorStore.instance.report(
      details.exception,
      details.stack ?? StackTrace.current,
      details.toString(),
    );

    return DebugErrorPanel(
      errorText: details.toString(),
      embedded: true,
    );
  };
}

class DebugErrorOverlay extends StatelessWidget {
  const DebugErrorOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    return Stack(
      children: [
        child,
        AnimatedBuilder(
          animation: DebugErrorStore.instance,
          builder: (context, _) {
            final errorText = DebugErrorStore.instance.lastError;
            if (errorText == null) return const SizedBox.shrink();

            return Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.88),
                child: SafeArea(
                  child: DebugErrorPanel(
                    errorText: errorText,
                    embedded: false,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class DebugErrorPanel extends StatelessWidget {
  const DebugErrorPanel({
    super.key,
    required this.errorText,
    required this.embedded,
  });

  final String errorText;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: embedded ? const Color(0xFF7F0000) : Colors.transparent,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Flutter error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: errorText));
                },
                child: const Text('Copy'),
              ),
              if (!embedded)
                TextButton(
                  onPressed: DebugErrorStore.instance.clear,
                  child: const Text('Close'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectionArea(
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> runAppWithDebugErrors(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    installDebugErrorHandlers();
  }

  runZonedGuarded(
    () => runApp(
      kDebugMode ? DebugErrorOverlay(child: app) : app,
    ),
    (Object error, StackTrace stack) {
      DebugErrorStore.instance.report(error, stack);
    },
  );
}
