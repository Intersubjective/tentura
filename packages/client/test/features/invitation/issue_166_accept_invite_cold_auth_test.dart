import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/exception.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// GitHub #166 — landing "add friend" / accept-invite handoff must complete on a
/// cold WASM screen without F5. Related: #73 (relationship updates), #97 (invite identity).
void main() {
  const code = 'Iabc166';
  const existingUserPreview = InvitePreview(
    codeStatus: InviteCodeStatus.available,
    callerStatus: InviteCallerStatus.existingUser,
    inviter: InvitePreviewInviter(id: 'Uinviter', displayName: 'Inviter'),
  );

  group('Issue #166 accept-invite cold auth', () {
    late _RecordingInvitationAcceptPort repo;
    late FakeUiEffectPort effects;
    late AcceptInviteCubit cubit;

    setUp(() {
      repo = _RecordingInvitationAcceptPort();
      effects = FakeUiEffectPort();
      cubit = AcceptInviteCubit.withPort(
        repo,
        effects: effects,
        postJoinNavigation: PostJoinNavigationCubit(),
      );
    });

    tearDown(() => cubit.close());

    test(
      'regression: first preview success reaches confirmation dialog state',
      () async {
        repo.previewResult = existingUserPreview;
        await cubit.start(code);
        expect(cubit.state.needsConfirmation, isTrue);
        expect(cubit.state.pendingInviter, const Profile(id: 'Uinviter', displayName: 'Inviter'));
        expect(repo.previewCalls, 1);
      },
    );

    test(
      'transient preview auth loss recovers to befriending without remount (issue #166)',
      () async {
        repo.previewHandler = () async {
          repo.previewCalls++;
          if (repo.previewCalls == 1) {
            throw const InvitationAuthLost();
          }
          return existingUserPreview;
        };

        await cubit.start(code);

        await _waitFor(
          () => cubit.state.needsConfirmation,
          timeout: const Duration(seconds: 2),
          onTimeout: () => 'Expected accept-invite to reach confirmation after '
              'session becomes ready (no F5). Last state: pendingSignup=${cubit.state.pendingSignupCode}, '
              'previewCalls=${repo.previewCalls}, status=${cubit.state.status}',
        );

        expect(cubit.state.pendingSignupCode, isNull);
        expect(repo.previewCalls, greaterThanOrEqualTo(2));

        effects.clear();
        await cubit.confirmAccept();
        expect(repo.acceptCalls, 1);
        expect(cubit.state.status, isA<StateIsSuccess>());
      },
    );
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  required Duration timeout,
  required String Function() onTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(onTimeout());
}

class _RecordingInvitationAcceptPort implements InvitationAcceptPort {
  int previewCalls = 0;
  int acceptCalls = 0;
  InvitePreview? previewResult;
  Future<InvitePreview> Function()? previewHandler;

  @override
  Future<InvitePreview> fetchInvitePreview(String code) async {
    if (previewHandler != null) {
      return previewHandler!();
    }
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
  }
}
