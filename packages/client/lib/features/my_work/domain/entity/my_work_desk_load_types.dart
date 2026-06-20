import 'my_work_card_view_model.dart';

typedef MyWorkDeskInitLoad = ({
  List<MyWorkCardViewModel> nonArchivedCards,
  int archivedCountHint,
  bool finishedArchiveHintDismissed,
});

typedef MyWorkDeskArchivedLoad = ({
  List<MyWorkCardViewModel> archivedCards,
});
