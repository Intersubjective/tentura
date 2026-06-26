import 'package:flutter_test/flutter_test.dart';
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
      expect(
        cubit.state.status,
        isA<StateIsNavigating>().having(
          (s) => s.path,
          'path',
          '/sign/up/I806d29daebbe',
        ),
      );
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
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<BeaconInviteAcceptedMessage>()),
      );
      expect(
        effects.emitted.whereType<NavigateReplace>().map((e) => e.target),
        contains(NavigateReplaceTarget.homeInboxTab),
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
      expect(
        cubit.state.status,
        isA<StateIsNavigating>().having(
          (s) => s.path,
          'path',
          '/sign/up/Iabc123',
        ),
      );
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
