import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_card_forwards_fold.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('forwards fold tolerates very narrow split-pane constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: _TestProfileCubit(),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 31,
                    child: InboxCardForwardsFold(
                      deadlineEndAt: DateTime.utc(2026, 7),
                      provenance: const InboxProvenance(
                        totalDistinctSenders: 1,
                        strongestNotePreview: '',
                        senders: [
                          InboxForwardSender(
                            id: 'sender',
                            displayName: 'Sender',
                            mr: 0.9,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
