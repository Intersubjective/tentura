import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../util/post_participants_sheet_request.dart';
import '../bloc/post_view_cubit.dart';

/// Opens «О посте» at participants once the Post screen has mounted.
class PostParticipantsSheetOpener extends StatefulWidget {
  const PostParticipantsSheetOpener({
    required this.postId,
    required this.child,
    this.openWhenReady = false,
    super.key,
  });

  final String postId;
  final bool openWhenReady;
  final Widget child;

  @override
  State<PostParticipantsSheetOpener> createState() =>
      _PostParticipantsSheetOpenerState();
}

class _PostParticipantsSheetOpenerState
    extends State<PostParticipantsSheetOpener> {
  var _opened = false;
  late final bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled =
        widget.openWhenReady ||
        PostParticipantsSheetRequest.instance.takeFor(widget.postId);
    if (_enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
    }
  }

  @override
  void didUpdateWidget(covariant PostParticipantsSheetOpener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.openWhenReady && widget.openWhenReady) {
      _opened = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
    }
  }

  Future<void> _maybeOpen() async {
    if (!mounted || !_enabled || _opened) return;
    final cubit = context.read<PostViewCubit>();
    // The stream ends without a match when the cubit closes first; a failed
    // load still reports success but leaves the placeholder Post (no author).
    final loaded = cubit.state.status is StateIsSuccess
        ? cubit.state
        : await cubit.stream.firstWhere(
            (s) => s.status is StateIsSuccess,
            orElse: () => cubit.state,
          );
    if (loaded.status is! StateIsSuccess || loaded.beacon.author.id.isEmpty) {
      return;
    }
    if (!mounted || !_enabled || _opened) return;
    _opened = true;
    await showPostInfoSheet(
      context,
      cubit: cubit,
      host: context.read<ThreadHostCubit>(),
      scrollToParticipants: true,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
