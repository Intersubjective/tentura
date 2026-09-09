typedef ConstellationLabelBudget = ({int perPerson, int total});

typedef ConstellationViewport = ({double width, double height});

const _kMaxLabelsPerPerson = 3;
const _kMaxLabelsTotal = 150;
const _kReferenceViewportWidth = 1200.0;
const _kReferenceViewportHeight = 900.0;

ConstellationLabelBudget constellationLabelBudget({
  required ConstellationViewport viewport,
  required double textScaleFactor,
}) {
  final safeScale = textScaleFactor <= 0 ? 1.0 : textScaleFactor;
  final areaRatio = (viewport.width * viewport.height) /
      (_kReferenceViewportWidth * _kReferenceViewportHeight);
  final densityFactor = areaRatio / safeScale;

  final perPerson = (_kMaxLabelsPerPerson * densityFactor)
      .floor()
      .clamp(1, _kMaxLabelsPerPerson);
  final total = (_kMaxLabelsTotal * densityFactor)
      .floor()
      .clamp(1, _kMaxLabelsTotal);

  return (perPerson: perPerson, total: total);
}

Map<String, List<String>> allocateVisibleRequests({
  required Map<String, List<String>> requestIdsByAuthor,
  required ConstellationLabelBudget budget,
}) {
  final authors = requestIdsByAuthor.keys.toList()..sort();
  final allocated = {for (final author in authors) author: <String>[]};

  var totalAllocated = 0;
  var round = 0;

  while (totalAllocated < budget.total) {
    var allocatedThisRound = false;

    for (final author in authors) {
      if (round >= budget.perPerson) {
        continue;
      }

      final requests = requestIdsByAuthor[author]!;
      if (round >= requests.length) {
        continue;
      }

      if (totalAllocated >= budget.total) {
        break;
      }

      allocated[author]!.add(requests[round]);
      totalAllocated++;
      allocatedThisRound = true;
    }

    if (!allocatedThisRound) {
      break;
    }
    round++;
  }

  return allocated;
}
