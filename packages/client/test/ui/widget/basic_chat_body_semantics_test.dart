// #723: the composer's Send (and Paste) button sat inside a second «button»
// node, the wrapper that carries its e2e identifier, so the accessibility
// tree showed «Send» twice, one inside the other. One node now carries the
// name, the tap and the identifier.
// #737: the Attach menu's Poll item had no usable name for screen readers.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/semantics_identifier.dart';

class _FakeImageRepository extends Fake implements ImageRepository {}

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

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

Future<void> _pumpBody(
  WidgetTester tester, {
  VoidCallback? onCreatePoll,
}) async {
  const width = 1400.0;
  await tester.binding.setSurfaceSize(const Size(width, 720));
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
          data: const MediaQueryData(size: Size(width, 720)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: const [],
                isLoading: false,
                imageRepository: _FakeImageRepository(),
                clipboardImageRepository: _FakeClipboardImageRepository(),
                enableComposerAttachments: true,
                enableParticipantMentions: false,
                onSend: (body, uploads) async => true,
                onToggleReaction: (_, _) async {},
                onCreatePoll: onCreatePoll,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<SemanticsNode> _nodes(bool Function(SemanticsNode node) test) =>
    find.semantics.byPredicate(test).evaluate().toList();

bool _isButton(SemanticsNode node) =>
    node.getSemanticsData().flagsCollection.isButton;

/// Buttons strictly below [node].
List<SemanticsNode> _buttonsInside(SemanticsNode node) {
  final out = <SemanticsNode>[];
  bool visit(SemanticsNode child) {
    if (_isButton(child)) out.add(child);
    child.visitChildren(visit);
    return true;
  }

  node.visitChildren(visit);
  return out;
}

/// The one node carrying [identifier] is the named, tappable button itself,
/// with no second button inside it or around it under the same name.
void _expectOneButtonNode(String identifier, String name) {
  final withId = _nodes(
    (n) => n.getSemanticsData().identifier == identifier,
  );
  expect(withId, hasLength(1), reason: identifier);
  final node = withId.single;
  expect(
    node,
    allOf(
      isSemantics(label: name, isButton: true, hasTapAction: true),
      hasSemanticsIdentifier(identifier),
    ),
  );
  expect(_buttonsInside(node), isEmpty, reason: 'a button inside $name');
  final named = _nodes((n) {
    final d = n.getSemanticsData();
    return _isButton(n) && (d.label == name || d.tooltip == name);
  });
  expect(named, hasLength(1), reason: 'buttons named $name');
}

void main() {
  testWidgets('Send is a single named button node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBody(tester);

    _expectOneButtonNode(TestIds.roomMessageSend, 'Send');
    handle.dispose();
  });

  testWidgets('Paste image is a single named button node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBody(tester);

    _expectOneButtonNode(TestIds.roomMessagePaste, 'Paste image');
    handle.dispose();
  });

  testWidgets('the Attach menu names the poll item for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var polls = 0;
    await _pumpBody(tester, onCreatePoll: () => polls++);

    await tester.tap(find.byKey(const ValueKey('attach')));
    await tester.pumpAndSettle();

    final poll = find.semantics.byLabel('Create poll');
    expect(poll, findsOne);
    expect(poll.evaluate().single, isSemantics(hasTapAction: true));

    tester.semantics.tap(poll);
    await tester.pumpAndSettle();
    expect(polls, 1);
    handle.dispose();
  });
}
