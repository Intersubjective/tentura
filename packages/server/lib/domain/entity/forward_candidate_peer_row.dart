import 'package:meta/meta.dart';

/// One mutually-visible peer from the `forwardCandidates` SQL wrap.
@immutable
class ForwardCandidatePeerRow {
  const ForwardCandidatePeerRow({
    required this.peerId,
    required this.forwardMr,
    required this.reverseMr,
    required this.viewerTrusts,
    required this.trustsViewer,
  });

  final String peerId;
  final double forwardMr;
  final double reverseMr;
  final bool viewerTrusts;
  final bool trustsViewer;
}
