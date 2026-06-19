enum MyWorkFilter {
  active,
  authored,
  helpOffered,
  drafts,
  all,
  archived,
}

/// Product menu order for My Desk filter dropdown (not [MyWorkFilter.values]).
const kMyWorkFilterMenuOrder = [
  MyWorkFilter.active,
  MyWorkFilter.authored,
  MyWorkFilter.helpOffered,
  MyWorkFilter.drafts,
  MyWorkFilter.all,
  MyWorkFilter.archived,
];
