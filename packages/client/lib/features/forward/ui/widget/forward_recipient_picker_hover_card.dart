import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/forward_candidate_context/ui/bloc/forward_candidate_context_cubit.dart';
import 'package:tentura/features/forward_candidate_context/ui/bloc/forward_candidate_context_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/capability_tag_presenter.dart';
import 'package:tentura/ui/util/profile_member_since.dart';

import '../model/forward_recipient_row_host.dart';

const _hoverShowDelay = Duration(milliseconds: 500);

bool _isDesktopHoverKind(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

/// Desktop-only hover preview for a picker recipient name (#440 mn5y.5).
class ForwardRecipientPickerNameHover extends StatefulWidget {
  const ForwardRecipientPickerNameHover({
    required this.candidate,
    required this.nameChild,
    required this.line2,
    required this.requiredCapabilitySlugs,
    this.connectionContextQuery = '',
    super.key,
  });

  final ForwardCandidate candidate;
  final Widget nameChild;
  final ForwardRecipientLine2 line2;
  final Set<String> requiredCapabilitySlugs;
  final String connectionContextQuery;

  @override
  State<ForwardRecipientPickerNameHover> createState() =>
      _ForwardRecipientPickerNameHoverState();
}

class _ForwardRecipientPickerNameHoverState
    extends State<ForwardRecipientPickerNameHover> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _showTimer;
  ForwardCandidateContextCubit? _contextCubit;
  var _hoverDepth = 0;

  @override
  void dispose() {
    _cancelShowTimer();
    _removeOverlay();
    unawaited(_contextCubit?.close());
    super.dispose();
  }

  void _cancelShowTimer() {
    _showTimer?.cancel();
    _showTimer = null;
  }

  void _scheduleShow() {
    if (_overlayEntry != null) return;
    _cancelShowTimer();
    _showTimer = Timer(_hoverShowDelay, _showOverlay);
  }

  void _onHoverEnter([PointerDeviceKind? kind]) {
    if (kind != null && !_isDesktopHoverKind(kind)) return;
    _hoverDepth++;
    _scheduleShow();
  }

  void _onHoverExit([PointerDeviceKind? kind]) {
    if (kind != null && !_isDesktopHoverKind(kind)) return;
    _hoverDepth = (_hoverDepth - 1).clamp(0, 999);
    if (_hoverDepth <= 0) {
      _hoverDepth = 0;
      _cancelShowTimer();
      _removeOverlay();
    }
  }

  void _showOverlay() {
    if (!mounted || _overlayEntry != null) return;
    _contextCubit ??= ForwardCandidateContextCubit(
      profile: widget.candidate.profile,
      context: widget.connectionContextQuery,
      loadCase: GetIt.I.isRegistered<LoadForwardCandidateContextCase>()
          ? GetIt.I<LoadForwardCandidateContextCase>()
          : null,
    )..load();
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(
      builder: (context) => _ForwardRecipientPickerHoverCardOverlay(
        layerLink: _layerLink,
        candidate: widget.candidate,
        line2: widget.line2,
        requiredCapabilitySlugs: widget.requiredCapabilitySlugs,
        contextCubit: _contextCubit!,
        onPointerEnter: () => _hoverDepth++,
        onPointerExit: () => _onHoverExit(),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Listener(
        onPointerHover: (event) {
          if (_isDesktopHoverKind(event.kind)) {
            _onHoverEnter(event.kind);
          }
        },
        child: MouseRegion(
          onEnter: (_) => _onHoverEnter(),
          onExit: (_) => _onHoverExit(),
          child: widget.nameChild,
        ),
      ),
    );
  }
}

class _ForwardRecipientPickerHoverCardOverlay extends StatelessWidget {
  const _ForwardRecipientPickerHoverCardOverlay({
    required this.layerLink,
    required this.candidate,
    required this.line2,
    required this.requiredCapabilitySlugs,
    required this.contextCubit,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  final LayerLink layerLink;
  final ForwardCandidate candidate;
  final ForwardRecipientLine2 line2;
  final Set<String> requiredCapabilitySlugs;
  final ForwardCandidateContextCubit contextCubit;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return CompositedTransformFollower(
      link: layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: Offset(0, tt.tightGap),
      child: MouseRegion(
        onEnter: (_) => onPointerEnter(),
        onExit: (_) => onPointerExit(),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            child: BlocProvider.value(
              value: contextCubit,
              child: ForwardRecipientPickerHoverCardBody(
                key: Key('forward.picker.hover.card.${candidate.id}'),
                candidate: candidate,
                line2: line2,
                requiredCapabilitySlugs: requiredCapabilitySlugs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ForwardRecipientPickerHoverCardBody extends StatelessWidget {
  const ForwardRecipientPickerHoverCardBody({
    required this.candidate,
    required this.line2,
    required this.requiredCapabilitySlugs,
    super.key,
  });

  final ForwardCandidate candidate;
  final ForwardRecipientLine2 line2;
  final Set<String> requiredCapabilitySlugs;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final reason = forwardRecipientPickerHoverReasonLine(line2);
    final requiredSet = {
      for (final s in requiredCapabilitySlugs)
        if (s.trim().isNotEmpty) s.trim(),
    };
    final matchingCaps = candidate.topCapabilities
        .where((slug) => requiredSet.contains(slug.trim()))
        .toList();

    return Padding(
      padding: tt.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reason != null && reason.isNotEmpty) ...[
            TenturaStatusText(
              reason,
              tone: line2.relationTone ?? TenturaTone.neutral,
            ),
            if (matchingCaps.isNotEmpty || candidate.profile.joinedAt != null)
              SizedBox(height: tt.tightGap),
          ],
          if (matchingCaps.isNotEmpty)
            Wrap(
              spacing: tt.iconTextGap,
              runSpacing: tt.tightGap,
              children: [
                for (final slug in matchingCaps)
                  if (CapabilityTag.fromSlug(slug.trim()) case final tag?)
                    Text(
                      '★ ${tag.labelOf(l10n)}',
                      style: TenturaText.labelSmall(tt.good),
                    ),
              ],
            ),
          if (matchingCaps.isNotEmpty && candidate.profile.joinedAt != null)
            SizedBox(height: tt.tightGap),
          _JoinedOnceContextLoaded(profile: candidate.profile),
        ],
      ),
    );
  }
}

class _JoinedOnceContextLoaded extends StatelessWidget {
  const _JoinedOnceContextLoaded({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final joinedAt = profile.joinedAt;
    if (joinedAt == null) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<
      ForwardCandidateContextCubit,
      ForwardCandidateContextState
    >(
      buildWhen: (prev, next) => prev.phase != next.phase,
      builder: (context, state) {
        if (state.phase == ForwardCandidateContextPhase.loading) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final line = profileMemberSinceDisplayLine(
          l10n: l10n,
          joinedAt: joinedAt,
          now: DateTime.now(),
        );
        return Text(line, style: TenturaText.bodySmall(context.tt.textMuted));
      },
    );
  }
}

/// Primary reason string for the picker hover card.
String? forwardRecipientPickerHoverReasonLine(ForwardRecipientLine2 line2) {
  if (line2.suppressed) return null;
  if (line2.tierEvidenceLabel != null) return line2.tierEvidenceLabel;
  if (line2.relationLabel != null) return line2.relationLabel;
  return line2.presenceOrAvailabilityLine;
}
