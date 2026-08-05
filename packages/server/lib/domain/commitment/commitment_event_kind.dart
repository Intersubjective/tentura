enum CommitmentEventKind {
  offered(0),
  acknowledged(1),
  acknowledgementSoftened(2),
  withdrawnByHelper(3),
  releasedByAuthor(4),
  removedFromChat(5),
  readmittedToChat(6),
  blockedCleanup(7),
  unansweredAtClose(8);

  const CommitmentEventKind(this.smallintValue);

  final int smallintValue;

  static CommitmentEventKind? tryFromInt(int? v) => switch (v) {
    0 => offered,
    1 => acknowledged,
    2 => acknowledgementSoftened,
    3 => withdrawnByHelper,
    4 => releasedByAuthor,
    5 => removedFromChat,
    6 => readmittedToChat,
    7 => blockedCleanup,
    8 => unansweredAtClose,
    _ => null,
  };
}
