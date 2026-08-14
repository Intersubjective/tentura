import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'beacon_view_screen.dart';

/// Resolves the thread segment for a message-only deep link.
Future<String> resolveCanonicalThreadIdForMessage({
  required BeaconThreadsCase threadsCase,
  required String beaconId,
  required String messageId,
}) async {
  final target = await threadsCase.fetchMessageTarget(
    beaconId: beaconId,
    messageId: messageId,
  );
  return target?.threadItemId ?? RequestThread.generalId;
}

@RoutePage(name: 'BeaconViewRoute')
class BeaconViewHostScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewHostScreen({
    @PathParam('id') required this.id,
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    @QueryParam(kQueryBeaconViewTab) this.viewTab,
    @QueryParam(kQueryBeaconPeopleTabAttention) this.peopleTabAttention,
    @QueryParam(kQueryBeaconEntry) this.entry,
    @QueryParam(kQueryThreadId) this.threadId,
    @QueryParam(kQueryMessageId) this.messageId,
    super.key,
  });

  final String id;
  final String? isDeepLink;
  final String? viewTab;
  final String? peopleTabAttention;
  final String? entry;
  final String? threadId;
  final String? messageId;

  @override
  Widget build(BuildContext context) => const AutoRouter();

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    child: BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (previous, current) =>
          previous.profile.id != current.profile.id,
      builder: (context, profileState) {
        final myProfile = profileState.profile;
        return BlocProvider(
          key: ValueKey('BeaconViewCubit:$id:${myProfile.id}'),
          create: (_) => BeaconViewCubit(
            myProfile: myProfile,
            id: id,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) {
                  final cubit = ThreadsCubit(beaconId: id);
                  unawaited(cubit.fetch());
                  return cubit;
                },
              ),
              BlocProvider(
                create: (_) => ThreadHostCubit(beaconId: id),
              ),
            ],
            child: _BeaconViewMessageCanonicalizer(
              beaconId: id,
              threadId: threadId,
              messageId: messageId,
              child: this,
            ),
          ),
        );
      },
    ),
  );
}

/// Resolves `?message=` without `?thread=` into the nested detail path once.
class _BeaconViewMessageCanonicalizer extends StatefulWidget {
  const _BeaconViewMessageCanonicalizer({
    required this.beaconId,
    required this.threadId,
    required this.messageId,
    required this.child,
  });

  final String beaconId;
  final String? threadId;
  final String? messageId;
  final Widget child;

  @override
  State<_BeaconViewMessageCanonicalizer> createState() =>
      _BeaconViewMessageCanonicalizerState();
}

class _BeaconViewMessageCanonicalizerState
    extends State<_BeaconViewMessageCanonicalizer> {
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_canonicalize()));
  }

  Future<void> _canonicalize() async {
    if (_started || !mounted) return;
    final explicitThread = widget.threadId?.trim();
    if (explicitThread != null && explicitThread.isNotEmpty) return;

    final messageId = widget.messageId?.trim();
    if (messageId == null || messageId.isEmpty) return;

    final childName = context.router.currentChild?.name;
    if (childName == ThreadDetailRoute.name) return;

    _started = true;
    final resolvedThreadId = await resolveCanonicalThreadIdForMessage(
      threadsCase: GetIt.I<BeaconThreadsCase>(),
      beaconId: widget.beaconId,
      messageId: messageId,
    );
    if (!mounted) return;

    await context.router.replace(
      ThreadDetailRoute(
        threadId: resolvedThreadId,
        messageId: messageId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

@RoutePage()
class BeaconViewOperationalScreen extends StatelessWidget {
  const BeaconViewOperationalScreen({
    @PathParam.inherit('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    @QueryParam(kQueryBeaconViewTab) this.viewTab,
    @QueryParam(kQueryBeaconPeopleTabAttention) this.peopleTabAttention,
    @QueryParam(kQueryBeaconEntry) this.entry,
    @QueryParam(kQueryThreadId) this.threadId,
    @QueryParam(kQueryMessageId) this.messageId,
    super.key,
  });

  final String id;
  final String? isDeepLink;
  final String? viewTab;
  final String? peopleTabAttention;
  final String? entry;
  final String? threadId;
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    return BeaconViewScreen(
      id: id,
      isDeepLink: isDeepLink,
      viewTab: viewTab,
      peopleTabAttention: peopleTabAttention,
      entry: entry,
      threadId: threadId,
      messageId: messageId,
    );
  }
}
