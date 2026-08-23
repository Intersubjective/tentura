import 'package:auto_route/auto_route.dart';
import 'package:tentura/consts.dart';

import 'home_tab_branches.dart';
import 'root_router.gr.dart';

/// Canonical root browse stack resolved from a canonical or legacy URL.
final class BrowseDeepLinkStack {
  const BrowseDeepLinkStack({required this.home, required this.detail});

  final HomeRoute home;
  final PageRouteInfo detail;
}

/// Centralized typed-stack builder for mutually navigable browse details.
///
/// Canonical links get a semantic Home source. Legacy `/home/<tab>/<detail>`
/// links retain their explicit source tab while normalizing the detail URL to
/// its canonical root path.
BrowseDeepLinkStack? buildBrowseDeepLinkStack(Uri input) {
  final parsed = _canonicalizeLegacy(input);
  final resolved = _detailFor(parsed.uri);
  if (resolved == null) return null;
  final owner = parsed.explicitOwner ?? resolved.owner;
  final spec = HomeTabSpec.forTab(owner);
  return BrowseDeepLinkStack(
    home: HomeRoute(
      children: [
        spec.shell(children: [spec.rootRoute()]),
      ],
    ),
    detail: resolved.route,
  );
}

({Uri uri, HomeTab? explicitOwner}) _canonicalizeLegacy(Uri input) {
  // `/home/inbox/rejected` is itself the canonical root detail path.
  if (input.path == kPathInboxRejected) {
    return (uri: input, explicitOwner: null);
  }
  for (final spec in HomeTabSpec.all) {
    final prefix = spec.path;
    if (!input.path.startsWith('$prefix/')) continue;
    var suffix = input.path.substring(prefix.length);
    if (suffix == '/inbox-rejected') suffix = kPathInboxRejected;
    return (
      uri: input.replace(path: suffix),
      explicitOwner: spec.tab,
    );
  }
  return (uri: input, explicitOwner: null);
}

({HomeTab owner, PageRouteInfo route})? _detailFor(Uri uri) {
  final path = uri.path;
  final query = Parameters(uri.queryParameters);

  final profileId = _singleId(path, kPathProfileView);
  if (profileId != null) {
    return (
      owner: HomeTab.network,
      route: ProfileViewRoute(id: profileId),
    );
  }

  final beaconMatch = RegExp(
    '^${RegExp.escape(kPathBeaconView)}/([^/]+)(?:/thread/([^/]+))?\$',
  ).firstMatch(path);
  if (beaconMatch != null) {
    final threadId = beaconMatch.group(2);
    return (
      owner: HomeTab.work,
      route: BeaconViewRoute(
        id: beaconMatch.group(1)!,
        isDeepLink: query.optString(kQueryIsDeepLink),
        viewTab: query.optString(kQueryBeaconViewTab),
        peopleTabAttention: query.optString(kQueryBeaconPeopleTabAttention),
        entry: query.optString(kQueryBeaconEntry),
        threadId: query.optString(kQueryThreadId),
        messageId: query.optString(kQueryMessageId),
        children: [
          BeaconViewOperationalRoute(
            isDeepLink: query.optString(kQueryIsDeepLink),
            viewTab: query.optString(kQueryBeaconViewTab),
            peopleTabAttention: query.optString(
              kQueryBeaconPeopleTabAttention,
            ),
            entry: query.optString(kQueryBeaconEntry),
            threadId: query.optString(kQueryThreadId),
            messageId: query.optString(kQueryMessageId),
          ),
          if (threadId != null)
            ThreadDetailRoute(
              threadId: threadId,
              isDeepLink: query.optString(kQueryIsDeepLink),
              viewTab: query.optString(kQueryBeaconViewTab),
              peopleTabAttention: query.optString(
                kQueryBeaconPeopleTabAttention,
              ),
              entry: query.optString(kQueryBeaconEntry),
              messageId: query.optString(kQueryMessageId),
            ),
        ],
      ),
    );
  }

  final beaconAllId = _singleId(path, kPathBeaconViewAll);
  if (beaconAllId != null) {
    return (owner: HomeTab.work, route: BeaconRoute(id: beaconAllId));
  }
  final involvedId = _singleId(path, kPathBeaconInvolvedAll);
  if (involvedId != null) {
    return (
      owner: HomeTab.work,
      route: InvolvedBeaconRoute(id: involvedId),
    );
  }
  final reviewId = _singleId(path, kPathReviewContributions);
  if (reviewId != null) {
    return (
      owner: HomeTab.work,
      route: ReviewContributionsRoute(
        id: reviewId,
        draft: query.getBool('draft', false),
      ),
    );
  }
  final receivedId = _singleId(path, kPathReceivedReviews);
  if (receivedId != null) {
    return (
      owner: HomeTab.work,
      route: ReceivedReviewsRoute(id: receivedId),
    );
  }

  final forwardsGraphId = _singleId(path, kPathForwardsGraph);
  if (forwardsGraphId != null) {
    return (
      owner: HomeTab.network,
      route: ForwardsGraphRoute(
        focus: forwardsGraphId,
        helpOffererId: query.optString('committer'),
        helpOffererName: query.optString('committerName'),
      ),
    );
  }
  final graphId = _singleId(path, kPathGraph);
  if (graphId != null) {
    return (owner: HomeTab.network, route: GraphRoute(focus: graphId));
  }
  if (path == kPathInviteGenealogy) {
    return (
      owner: HomeTab.network,
      route: InviteGenealogyRoute(
        targetId: query.optString(kQueryGenealogyWith),
      ),
    );
  }
  if (path == kPathRating) {
    return (owner: HomeTab.network, route: const RatingRoute());
  }
  if (path == kPathInboxRejected) {
    return (owner: HomeTab.inbox, route: const InboxRejectedRoute());
  }
  return null;
}

String? _singleId(String path, String prefix) {
  if (!path.startsWith('$prefix/')) return null;
  final id = path.substring(prefix.length + 1);
  return id.isEmpty || id.contains('/') ? null : id;
}
