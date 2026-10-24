// #470: the "Trust change not saved" bar carries a Retry action, so the
// SnackBar defaulted to `persist: true` and stayed until closed by hand. It is
// not a blocking error: it must auto-dismiss within 6 s like other bars.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_trust_write_notices.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}

  void revert(GraphTrustRevert revert) =>
      emit(state.copyWith(trustError: revert));
}

void main() {
  testWidgets('trust-not-saved bar with Retry auto-dismisses within 6 s', (
    tester,
  ) async {
    final cubit = _StubContextCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: BlocProvider<GraphPersonContextCubit>.value(
            value: cubit,
            child: const GraphTrustWriteNotices(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    cubit.revert(
      const GraphTrustRevert(
        profile: Profile(id: 'peer', displayName: 'Peer'),
        acknowledgedAmount: 0,
        intendedAmount: 1,
      ),
    );
    // Listener fires, bar enters, messenger arms its timer once fully shown.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.text('Trust change not saved', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  // #495: the bar queued behind one already on screen and waited out its
  // whole duration; it replaces it now, like every app bar.
  testWidgets('trust-not-saved bar replaces a bar already on screen', (
    tester,
  ) async {
    final cubit = _StubContextCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: BlocProvider<GraphPersonContextCubit>.value(
            value: cubit,
            child: const GraphTrustWriteNotices(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .showSnackBar(
          const SnackBar(
            content: Text('Earlier bar'),
            duration: Duration(seconds: 30),
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Earlier bar'), findsOneWidget);

    cubit.revert(
      const GraphTrustRevert(
        profile: Profile(id: 'peer', displayName: 'Peer'),
        acknowledgedAmount: 0,
        intendedAmount: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Earlier bar'), findsNothing);
    expect(
      find.text('Trust change not saved', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
