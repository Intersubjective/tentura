enum CandidateInvolvement {
  unseen,
  forwarded,
  committed,
  withdrawn,
  declined,
  author;

  bool get isInvolved => this != CandidateInvolvement.unseen;
}
