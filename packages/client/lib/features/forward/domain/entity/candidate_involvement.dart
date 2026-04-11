enum CandidateInvolvement {
  unseen,
  forwarded,
  forwardedByMe,
  watching,
  committed,
  withdrawn,
  declined,
  author;

  bool get isInvolved =>
      this != CandidateInvolvement.unseen &&
      this != CandidateInvolvement.forwarded;
}
