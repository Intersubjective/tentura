enum CandidateInvolvement {
  unseen,
  forwarded,
  forwardedByMe,
  watching,
  helpOffered,
  withdrawn,
  offerDeclinedByAuthor,
  declined,
  author;

  bool get isInvolved =>
      this != CandidateInvolvement.unseen &&
      this != CandidateInvolvement.forwarded;
}
