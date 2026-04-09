enum CandidateInvolvement {
  unseen,
  forwarded,
  watching,
  committed,
  withdrawn,
  declined,
  author;

  bool get isInvolved => this != CandidateInvolvement.unseen;
}
