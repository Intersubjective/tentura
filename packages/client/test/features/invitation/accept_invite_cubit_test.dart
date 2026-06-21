import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/invitation/domain/exception.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/ui/bloc/state_base.dart';

void main() {
  group('AcceptInviteCubit', () {
    late FakeInvitationAcceptPort repo;
    late AcceptInviteCubit cubit;

    setUp(() {
      repo = FakeInvitationAcceptPort();
      cubit = AcceptInviteCubit.withPort(repo);
    });

    tearDown(() => cubit.close());

    test('invalid code emits messaging without preview call', () async {
      await cubit.start('bad');
      expect(repo.previewCalls, 0);
      expect(
        cubit.state.status,
        isA<StateIsMessaging>().having(
          (s) => s.message,
          'message',
          isA<InviteInvalidCodeMessage>(),
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
      expect(
        cubit.state.status,
        isA<StateIsMessaging>().having(
          (s) => s.message,
          'message',
          isA<InviteAlreadyFriendsMessage>(),
        ),
      );
    });

    test('existing-user awaits confirmation', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
      );
      await cubit.start('Iabc123');
      expect(cubit.state.needsConfirmation, isTrue);
      expect(cubit.state.pendingInviter, const Profile(id: 'U1', displayName: 'Alice'));
    });

    test('confirmAccept posts accept-as-existing', () async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U1', displayName: 'Alice'),
      );
      await cubit.start('Iabc123');
      await cubit.confirmAccept();
      expect(repo.acceptCalls, 1);
      expect(
        cubit.state.status,
        isA<StateIsMessaging>().having(
          (s) => s.message,
          'message',
          isA<InviteAcceptedMessage>(),
        ),
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
      await cubit.confirmAccept();
      expect(
        cubit.state.status,
        isA<StateIsMessaging>().having(
          (s) => s.message,
          'message',
          isA<InviteNoLongerValidMessage>(),
        ),
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
        isA<StateIsNavigating>().having((s) => s.path, 'path', '/sign/up/Iabc123'),
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
