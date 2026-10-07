import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/beacon_view_route_normalizer.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'beacon_view_screen.dart';
import 'beacon_view_scope.dart';

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
    child: _BeaconKindGate(
      beaconId: id,
      builder: (kind) => BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (previous, current) =>
            previous.profile.id != current.profile.id,
        builder: (context, profileState) {
          final myProfile = profileState.profile;
          if (kind == BeaconKind.post) return _postScope(myProfile);
          return _requestScope(myProfile);
        },
      ),
    ),
  );

  // The Post's own route keeps Home's rail beside it, like every browse
  // route; Inbox's list-detail pane builds the same scope without it.
  Widget _postScope(Profile myProfile) => HomeRailFrame(
    selectedTab: HomeTab.conversations,
    child: PostViewScope(id: id, myProfile: myProfile),
  );

  Widget _requestScope(Profile myProfile) => BeaconViewScope(
    id: id,
    myProfile: myProfile,
    child: _BeaconViewMessageCanonicalizer(
      beaconId: id,
      threadId: threadId,
      messageId: messageId,
      isDeepLink: isDeepLink,
      entry: entry,
      child: this,
    ),
  );
}

/// Resolves the beacon kind once, then builds the matching scope.
class _BeaconKindGate extends StatefulWidget {
  const _BeaconKindGate({required this.beaconId, required this.builder});

  final String beaconId;
  final Widget Function(BeaconKind kind) builder;

  @override
  State<_BeaconKindGate> createState() => _BeaconKindGateState();
}

class _BeaconKindGateState extends State<_BeaconKindGate> {
  late Future<BeaconKind> _kind = _resolve();

  Future<BeaconKind> _resolve() async {
    try {
      return await GetIt.I<BeaconKindRepository>().fetchKind(widget.beaconId);
    } on Object {
      // The Request screen owns load-error presentation.
      return BeaconKind.request;
    }
  }

  @override
  void didUpdateWidget(_BeaconKindGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beaconId != widget.beaconId) _kind = _resolve();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BeaconKind>(
    future: _kind,
    builder: (context, snapshot) => snapshot.hasData
        ? widget.builder(snapshot.requireData)
        : const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          ),
  );
}

/// Resolves `?message=` without `?thread=` into the nested detail path once.
class _BeaconViewMessageCanonicalizer extends StatefulWidget {
  const _BeaconViewMessageCanonicalizer({
    required this.beaconId,
    required this.threadId,
    required this.messageId,
    required this.isDeepLink,
    required this.entry,
    required this.child,
  });

  final String beaconId;
  final String? threadId;
  final String? messageId;
  final String? isDeepLink;
  final String? entry;
  final Widget child;

  @override
  State<_BeaconViewMessageCanonicalizer> createState() =>
      _BeaconViewMessageCanonicalizerState();
}

class _BeaconViewMessageCanonicalizerState
    extends State<_BeaconViewMessageCanonicalizer> {
  /// Set only after a successful in-place ROOM hand-off (plan §4.6).
  String? _resolvedForMessageId;

  int _intentGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_canonicalize()),
    );
  }

  @override
  void didUpdateWidget(_BeaconViewMessageCanonicalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.threadId != widget.threadId) {
      if (oldWidget.messageId != widget.messageId) {
        _resolvedForMessageId = null;
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_canonicalize()),
      );
    }
  }

  Future<void> _canonicalize() async {
    if (!mounted) return;
    final explicitThread = widget.threadId?.trim();
    if (explicitThread != null && explicitThread.isNotEmpty) return;

    final messageId = widget.messageId?.trim();
    if (messageId == null || messageId.isEmpty) return;
    if (_resolvedForMessageId == messageId) return;

    final generation = ++_intentGeneration;

    String resolvedThreadId;
    try {
      resolvedThreadId = await resolveCanonicalThreadIdForMessage(
        threadsCase: GetIt.I<BeaconThreadsCase>(),
        beaconId: widget.beaconId,
        messageId: messageId,
      );
    } on Object {
      return;
    }
    if (!mounted || generation != _intentGeneration) return;

    final normalized = normalizeBeaconViewRouteQuery(
      pathThreadId: resolvedThreadId,
      incomingQuery: {
        if (widget.isDeepLink != null) kQueryIsDeepLink: widget.isDeepLink!,
        if (widget.entry != null) kQueryBeaconEntry: widget.entry!,
        kQueryMessageId: messageId,
      },
    );

    await context.router.replace(
      beaconViewOperationalFromNormalized(normalized),
    );
    if (!mounted || generation != _intentGeneration) return;

    _resolvedForMessageId = messageId;
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
