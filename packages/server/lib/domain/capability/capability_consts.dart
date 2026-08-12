/// Subjective help-tag evidence tuning constants (plan §2).
///
/// Half-lives are in **seconds** — SQL `cap_strength` / `cap_cell_rebuild` take
/// `_half_life_seconds`; a `…Days` constant passed straight in decays 86,400× too fast.
const double kCapKOut = 2.0;
const int kCapHalfLifeOutSeconds = 365 * 86400; // 31536000

const double kCapKSeed = 1.0;
const int kCapHalfLifeSeedSeconds = 90 * 86400; // 7776000

const double kCapThetaOut = 0.30;
const int kCapWindowMonths = 24;

const double kCapThetaSeed = 0.25;
const double kCapFloorPercentile = 0.33;

const int kCapWitnessWindowK = 200;

const int kCapBandEvidenceSlots = 3;
const int kCapExplorationSlots = 2;

const int kCapMaxTagsPerSubjectBeacon = 3;
const int kCapExplorationRecentForwardDays = 30;

const int kCapWindowTtlMinutes = 15;
