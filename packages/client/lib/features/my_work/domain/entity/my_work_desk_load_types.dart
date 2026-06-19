import 'my_work_card_view_model.dart';

typedef MyWorkDeskInitLoad = ({
  List<MyWorkCardViewModel> nonArchivedCards,
  List<String> authoredClosedIdHints,
  List<String> helpOfferedClosedIdHints,
});

typedef MyWorkDeskClosedLoad = ({
  List<MyWorkCardViewModel> archivedCards,
});
