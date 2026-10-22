import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/invitation/domain/exception.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

void main() {
  group('AcceptInviteCubit', () {
    late FakeInvitationAcceptPort repo;
    late FakeUiEffectPort effects;
    late PostJoinNavigationCubit postJoin;
    late AcceptInviteCubit cubit;

    setUp(() {
      repo = FakeInvitationAcceptPort();
      effects = FakeUiEffectPort();
      postJoin = PostJoinNavigationCubit();
      cubit = AcceptInviteCubit.withPort(
        repo,
        effects: effects,
        postJoinNavigation: postJoin,
      );
    });

    tearDown(() => cubit.close());

    test('invalid code emits messaging without preview call', () async {
      await cubit.start('bad');
      expect(repo.previewCalls, 0);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<InviteInvalidCodeMessage>()),
      );
      expect(
        effects.emitted.whereType<NavigateReplace>(),
        isNotEmpty,
      );
    });

    test('trailing dash normalizes before preview', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.anonymous,
      );
      await cubit.start('I806d29daebbe-');
      expect(repo.previewCalls, 1);
      expect(cubit.state.code, 'I806d29daebbe');
      expect(cubit.state.pendingSignupCode, 'I806d29daebbe');
    });

    test('already-friends short-circuits without accept POST', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.alreadyFriends,
      );
      await cubit.start('Iabc123');
      expect(repo.acceptCalls, 0);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<InviteAlreadyFriendsMessage>()),
      );
    });

    // #272: opening your own invite link while signed in says plainly that
    // it is yours, how to use it, and offers to copy the link.
    test('own invite link explains itself and offers Copy link', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.isInviter,
      );
      await cubit.start('Iabc123');
      expect(repo.acceptCalls, 0);
      final message = effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<InviteOwnInviteLinkMessage>()
          .single;
      expect(message.code, 'Iabc123');
      expect(message.toEn, contains('your own invite link'));
      expect(message.toEn, contains('private browser window'));
      expect(message.toRu, contains('приватном окне'));
      expect(message.label.toEn, 'Copy link');
      expect(message.label.toRu, 'Копировать ссылку');
      expect(effects.emitted.whereType<NavigateReplace>(), isNotEmpty);
    });

    test('existing-user awaits confirmation', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
        beacon: InvitePreviewBeacon(id: 'B1', title: 'Help needed'),
      );
      await cubit.start('Iabc123');
      expect(cubit.state.needsConfirmation, isTrue);
      expect(
        cubit.state.pendingInviter,
        const Profile(id: 'U1', displayName: 'Alice'),
      );
      expect(cubit.state.pendingBeacon?.id, 'B1');
    });

    test(
      'existing-user confirmation carries the inviter photo (#388)',
      () async {
        repo.previewResult = InvitePreview(
          codeStatus: InviteCodeStatus.available,
          callerStatus: InviteCallerStatus.existingUser,
          inviter: InvitePreviewInviter.fromJson({
            'id': 'U1',
            'displayName': 'Alice',
            'image': '$kImageServer/$kImagesPath/U1/img42.$kImageExt',
          }),
        );
        await cubit.start('Iabc123');
        final inviter = cubit.state.pendingInviter!;
        expect(inviter.hasAvatar, isTrue);
        expect(
          inviter.avatarUrl,
          '$kImageServer/$kImagesPath/U1/img42.$kImageExt',
        );
      },
    );

    test('confirmAccept with beacon navigates to inbox tab', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
        beacon: InvitePreviewBeacon(id: 'B1', title: 'Help needed'),
      );
      await cubit.start('Iabc123');
      effects.clear();
      await cubit.confirmAccept();
      expect(repo.acceptCalls, 1);
      expect(effects.emitted.whereType<ShowMessage>(), isEmpty);
      expect(
        effects.emitted.whereType<NavigateReplace>().map((e) => e.target),
        contains(NavigateReplaceTarget.homeInboxTab),
      );
      final dest = postJoin.takeDestination();
      expect(dest?.beaconId, 'B1');
      expect(dest?.showSnackbar, isTrue);
    });

    // #501: a Post invite keeps saying "post" after accepting.
    test('a Post invite carries its kind to the post-join message', () async {
      repo.previewResult = InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: const InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
        beacon: InvitePreviewBeacon.fromJson(const {
          'id': 'P1',
          'title': '',
          'kind': 'post',
        }),
      );
      await cubit.start('Iabc123');
      await cubit.confirmAccept();
      final dest = postJoin.takeDestination();
      expect(dest?.beaconId, 'P1');
      expect(dest?.isPost, isTrue);

      final message = BeaconInviteAcceptedMessage(
        inviterName: 'Alice',
        beaconId: 'P1',
        beaconTitle: '',
        isPost: dest!.isPost,
      );
      expect(message.toEn, 'Alice shared a post with you.');
      expect(message.toRu, 'Alice поделился(ась) с вами постом.');
      expect(message.label.toEn, 'Open post');
      expect(
        InvitePreviewBeacon.fromJson(const {'id': 'B1', 'title': 'x'}).isPost,
        isFalse,
      );
    });

    test('confirmAccept posts accept-as-existing', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
      );
      await cubit.start('Iabc123');
      effects.clear();
      await cubit.confirmAccept();
      expect(repo.acceptCalls, 1);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<InviteAcceptedMessage>()),
      );
    });

    test('404 after confirm is non-fatal messaging', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
      );
      repo.acceptError = const InvitationNoLongerValid();
      await cubit.start('Iabc123');
      effects.clear();
      await cubit.confirmAccept();
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<InviteNoLongerValidMessage>()),
      );
    });

    test('anonymous preview navigates to signup path', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.anonymous,
      );
      await cubit.start('Iabc123');
      expect(cubit.state.pendingSignupCode, 'Iabc123');
    });
  });
}

class FakeInvitationAcceptPort implements InvitationAcceptPort {
  FakeInvitationAcceptPort();

  InvitePreview? previewResult;
  InvitationException? acceptError;
  int previewCalls = 0;
  int acceptCalls = 0;

  @override
  Future<InvitePreview> fetchInvitePreview(String code) async {
    previewCalls++;
    return previewResult ??
        const InvitePreview(
          codeStatus: InviteCodeStatus.invalid,
          callerStatus: InviteCallerStatus.anonymous,
        );
  }

  @override
  Future<void> acceptExistingInvite(String code) async {
    acceptCalls++;
    if (acceptError != null) {
      throw acceptError!;
    }
  }
}
