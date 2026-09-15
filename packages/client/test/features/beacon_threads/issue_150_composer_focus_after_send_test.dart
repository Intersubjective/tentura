import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
        profile: Profile(id: 'me', displayName: 'Me'),
      );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

Finder _discussionComposerField() {
  return find.descendant(
    of: find.byType(BeaconRoomComposer),
    matching: find.byType(TextField),
  );
}

bool _composerFieldHasFocus(WidgetTester tester) {
  final field = tester.widget<TextField>(_discussionComposerField());
  final node = field.focusNode;
  return node != null && node.hasFocus;
}

Future<void> _pumpDiscussionComposer(
  WidgetTester tester, {
  required Future<bool> Function(String body) onSend,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 720)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: const [],
                isLoading: false,
                imageRepository: ImageRepository(),
                clipboardImageRepository: ClipboardImageRepository(),
                enableComposerAttachments: false,
                onSend: (body, _) => onSend(body),
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _focusDiscussionComposer(WidgetTester tester) async {
  await tester.tap(_discussionComposerField());
  await tester.pump();
}

void main() {
  group('issue #150 discussion composer focus after send', () {
    testWidgets(
      'send button keeps keyboard focus on composer for immediate second message',
      (tester) async {
        var sendCount = 0;
        await _pumpDiscussionComposer(
          tester,
          onSend: (_) async {
            sendCount++;
            return true;
          },
        );

        await _focusDiscussionComposer(tester);
        expect(_composerFieldHasFocus(tester), isTrue);

        await tester.enterText(_discussionComposerField(), 'first');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(sendCount, 1);
        expect(
          _composerFieldHasFocus(tester),
          isTrue,
          reason:
              'composer should retain focus after send so the user can type again without clicking',
        );

        await tester.enterText(_discussionComposerField(), 'second');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(sendCount, 2);
        expect(_composerFieldHasFocus(tester), isTrue);
      },
    );

    testWidgets(
      'keyboard send action keeps focus for type-send-type-send without mouse',
      (tester) async {
        var sendCount = 0;
        await _pumpDiscussionComposer(
          tester,
          onSend: (_) async {
            sendCount++;
            return true;
          },
        );

        await _focusDiscussionComposer(tester);
        expect(_composerFieldHasFocus(tester), isTrue);

        await tester.enterText(_discussionComposerField(), 'alpha');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();

        expect(sendCount, 1);
        expect(
          _composerFieldHasFocus(tester),
          isTrue,
          reason:
              'Enter/send action should return focus to composer for the next line',
        );

        await tester.enterText(_discussionComposerField(), 'beta');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();

        expect(sendCount, 2);
        expect(_composerFieldHasFocus(tester), isTrue);
      },
    );

    testWidgets(
      'primary focus stays on composer not send control after successful send',
      (tester) async {
        await _pumpDiscussionComposer(tester, onSend: (_) async => true);

        await _focusDiscussionComposer(tester);
        await tester.enterText(_discussionComposerField(), 'hello');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final primary = FocusManager.instance.primaryFocus;
        final composerNode =
            tester.widget<TextField>(_discussionComposerField()).focusNode;

        expect(
          primary,
          isNotNull,
          reason: 'something should hold primary focus after send',
        );
        expect(
          primary,
          same(composerNode),
          reason:
              'primary focus should remain on the discussion composer TextField',
        );
      },
    );
  });
}
