/// Wall-clock boundary for time-dependent domain policies.
// ignore: one_member_abstracts -- injectable boundary with a test replacement
abstract interface class ClockPort {
  DateTime now();
}
