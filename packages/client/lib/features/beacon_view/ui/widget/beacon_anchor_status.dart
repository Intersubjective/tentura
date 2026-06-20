import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

/// Semantic tone for the operational "anchor" status line (coordination + help offers).
TenturaTone beaconAnchorStatusTone(BeaconCoordinationStatus s) => switch (s) {
      BeaconCoordinationStatus.neutral => TenturaTone.neutral,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => TenturaTone.warn,
      BeaconCoordinationStatus.enoughHelpOffered => TenturaTone.good,
    };

TenturaTone coordinationResponseTone(CoordinationResponseType r) => switch (r) {
      CoordinationResponseType.useful => TenturaTone.good,
      CoordinationResponseType.overlapping => TenturaTone.info,
      CoordinationResponseType.needDifferentSkill => TenturaTone.danger,
      CoordinationResponseType.needCoordination => TenturaTone.info,
      CoordinationResponseType.notSuitable => TenturaTone.danger,
    };

/// Two-slot operational status for beacon detail surfaces (app bar subtitle).
final class BeaconViewStatusSlots {
  const BeaconViewStatusSlots({
    required this.slot1,
    required this.slot2,
    required this.tone,
  });

  final String slot1;
  final String slot2;
  final TenturaTone tone;

  bool get isEmpty => slot1.trim().isEmpty && slot2.trim().isEmpty;

  String get displayLine {
    final s1 = slot1.trim();
    final s2 = slot2.trim();
    if (s1.isEmpty && s2.isEmpty) return '';
    if (s1.isEmpty) return s2;
    if (s2.isEmpty) return s1;
    return '$s1 · $s2';
  }
}

/// Role-aware two-slot status from [BeaconViewState] (mirrors My Work card grammar).
BeaconViewStatusSlots beaconViewStatusSlots(
  L10n l10n,
  BeaconViewState state, {
  DateTime? now,
}) {
  final b = state.beacon;
  final clock = now ?? DateTime.now();

  if (b.lifecycle == BeaconLifecycle.deleted) {
    return BeaconViewStatusSlots(
      slot1: l10n.beaconHudBeaconUnavailable,
      slot2: '',
      tone: TenturaTone.neutral,
    );
  }

  if (b.lifecycle == BeaconLifecycle.closed ||
      b.lifecycle == BeaconLifecycle.cancelled) {
    final slot1 = b.lifecycle == BeaconLifecycle.cancelled
        ? l10n.myWorkStatusCancelled
        : l10n.myWorkStatusClosed;
    if (state.isHelpOffered) {
      return BeaconViewStatusSlots(
        slot1: _helpOfferSlot1WithResponse(
          l10n,
          state.myActiveHelpOffer?.coordinationResponse,
          slot1,
        ),
        slot2: '',
        tone: _toneForHelpOffer(state.myActiveHelpOffer?.coordinationResponse),
      );
    }
    return BeaconViewStatusSlots(
      slot1: slot1,
      slot2: '',
      tone: TenturaTone.neutral,
    );
  }

  if (b.lifecycle == BeaconLifecycle.reviewOpen) {
    final review = _reviewWindowSlot(l10n, b, clock);
    final response = state.isHelpOffered
        ? state.myActiveHelpOffer?.coordinationResponse
        : null;
    return BeaconViewStatusSlots(
      slot1: l10n.myWorkStatusWrappingUp,
      slot2: review.text,
      tone: response != null
          ? _toneForHelpOffer(response)
          : TenturaTone.neutral,
    );
  }

  if (state.isBeaconMine) {
    return _authoredOpenSlots(l10n, b);
  }

  if (state.isHelpOffered) {
    return _helpOfferedOpenSlots(l10n, b, state);
  }

  return _viewerOpenSlots(l10n, b);
}

BeaconViewStatusSlots _authoredOpenSlots(L10n l10n, Beacon b) {
  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.neutral => const BeaconViewStatusSlots(
        slot1: '',
        slot2: '',
        tone: TenturaTone.neutral,
      ),
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusNeedsMoreHelp,
        slot2: '',
        tone: TenturaTone.warn,
      ),
    BeaconCoordinationStatus.enoughHelpOffered => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusEnoughHelp,
        slot2: '',
        tone: TenturaTone.good,
      ),
  };
}

BeaconViewStatusSlots _helpOfferedOpenSlots(
  L10n l10n,
  Beacon b,
  BeaconViewState state,
) {
  final response = state.myActiveHelpOffer?.coordinationResponse;
  if (response != null) {
    return BeaconViewStatusSlots(
      slot1: _helpOfferSlot1WithResponse(
        l10n,
        response,
        l10n.myWorkStatusHelpOfferedPersonal,
      ),
      slot2: '',
      tone: _toneForHelpOffer(response),
    );
  }

  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.neutral => const BeaconViewStatusSlots(
        slot1: '',
        slot2: '',
        tone: TenturaTone.neutral,
      ),
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusNeedsMoreHelp,
        slot2: '',
        tone: TenturaTone.warn,
      ),
    BeaconCoordinationStatus.enoughHelpOffered => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusEnoughHelp,
        slot2: '',
        tone: TenturaTone.good,
      ),
  };
}

BeaconViewStatusSlots _viewerOpenSlots(L10n l10n, Beacon b) {
  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.neutral => const BeaconViewStatusSlots(
        slot1: '',
        slot2: '',
        tone: TenturaTone.neutral,
      ),
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusNeedsMoreHelp,
        slot2: '',
        tone: TenturaTone.warn,
      ),
    BeaconCoordinationStatus.enoughHelpOffered => BeaconViewStatusSlots(
        slot1: l10n.myWorkStatusEnoughHelp,
        slot2: '',
        tone: TenturaTone.good,
      ),
  };
}

String _helpOfferSlot1WithResponse(
  L10n l10n,
  CoordinationResponseType? response,
  String helpOfferStatusLabel,
) {
  final resp = coordinationResponseLabel(l10n, response);
  if (resp == null) {
    return helpOfferStatusLabel;
  }
  return l10n.myWorkStatusHelpOfferWithResponse(
    helpOfferStatusLabel.toLowerCase(),
    resp.toLowerCase(),
  );
}

TenturaTone _toneForHelpOffer(CoordinationResponseType? response) {
  if (response == null) return TenturaTone.neutral;
  return coordinationResponseTone(response);
}

({String text, bool overdue}) _reviewWindowSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  final closesAt = b.reviewClosesAt;
  if (closesAt == null || b.reviewWindowStatus == 1) {
    return (text: '', overdue: false);
  }
  final remaining = closesAt.toUtc().difference(now.toUtc());
  if (remaining.isNegative) {
    return (text: '', overdue: false);
  }
  return (
    text: formatCompactDurationRemaining(remaining, l10n),
    overdue: false,
  );
}

/// Localized anchor line: coordination label · help offers fragment.
String beaconAnchorStatusLine(
  L10n l10n,
  Beacon beacon,
  int activeHelpOfferCount,
) {
  final coord = coordinationStatusLabel(l10n, beacon.coordinationStatus);
  final helpOfferedPart = activeHelpOfferCount == 0
      ? l10n.beaconHeaderNoHelpOffers
      : l10n.beaconHeaderHelpOffersCount(activeHelpOfferCount);
  return '$coord · $helpOfferedPart';
}

/// Terse anchor line for compact surfaces (e.g. AppBar): ALL-CAPS code · count.
@Deprecated('Use beaconViewStatusSlots instead')
String beaconAnchorStatusLineShort(
  Beacon beacon,
  int activeHelpOfferCount,
) =>
    switch (beacon.coordinationStatus) {
      BeaconCoordinationStatus.neutral => 'IDLE',
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        activeHelpOfferCount > 0 ? 'GAP · $activeHelpOfferCount' : 'GAP',
      BeaconCoordinationStatus.enoughHelpOffered =>
        activeHelpOfferCount > 0 ? 'OK · $activeHelpOfferCount' : 'OK',
    };
