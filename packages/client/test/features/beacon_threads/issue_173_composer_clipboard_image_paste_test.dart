import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
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

class _TrackingClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  _TrackingClipboardImageRepository(this._result);

  final ClipboardImageReadResult _result;
  int readImageCalls = 0;

  @override
  Future<ClipboardImageReadResult> readImage() async {
    readImageCalls++;
    return _result;
  }
}

class _NoPickerImageRepository extends Fake implements ImageRepository {
  int pickMultipleImagesCalls = 0;

  @override
  Future<List<ImagePicked>> pickMultipleImages() async {
    pickMultipleImagesCalls++;
    fail(
      'discussion composer keyboard paste must not open the image file picker',
    );
  }
}

Finder _discussionComposerField() {
  return find.descendant(
    of: find.byType(BeaconRoomComposer),
    matching: find.byType(TextField),
  );
}

Future<void> _pumpDiscussionComposerWithAttachments(
  WidgetTester tester, {
  required ClipboardImageRepository clipboardImageRepository,
  required ImageRepository imageRepository,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 720));
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
          data: const MediaQueryData(size: Size(1400, 720)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: const [],
                isLoading: false,
                imageRepository: imageRepository,
                clipboardImageRepository: clipboardImageRepository,
                enableComposerAttachments: true,
                onSend: (_, __) async => true,
                onToggleReaction: (_, __) async {},
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
  final field = tester.widget<TextField>(_discussionComposerField());
  expect(field.focusNode?.hasFocus, isTrue);
}

Future<void> _sendKeyboardPaste(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();

  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.metaLeft,
    platform: 'macos',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.pumpAndSettle();
}

void main() {
  group('issue #173 discussion composer clipboard image paste', () {
    testWidgets(
      'Ctrl/Cmd+V attaches clipboard image without opening file picker',
      (tester) async {
        final upload = RoomPendingUpload(
          bytes: Uint8List.fromList([9, 8, 7]),
          fileName: 'clipboard.png',
          mimeType: 'image/png',
        );
        final clipboard = _TrackingClipboardImageRepository(
          ClipboardImageReadResult.found(upload),
        );
        final images = _NoPickerImageRepository();

        await _pumpDiscussionComposerWithAttachments(
          tester,
          clipboardImageRepository: clipboard,
          imageRepository: images,
        );
        await _focusDiscussionComposer(tester);

        await _sendKeyboardPaste(tester);

        expect(
          clipboard.readImageCalls,
          greaterThan(0),
          reason:
              'keyboard paste should read the clipboard via ClipboardImageRepository',
        );
        expect(
          images.pickMultipleImagesCalls,
          0,
          reason: 'keyboard paste must not route through pickMultipleImages',
        );
        expect(
          find.descendant(
            of: find.byType(BeaconRoomComposer),
            matching: find.byType(Image),
          ),
          findsOneWidget,
          reason:
              'pasted image bytes should appear as a pending attachment preview',
        );
      },
    );
  });
}
