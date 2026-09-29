const settlementVersion = 1;

final class SettlementParams {
  const SettlementParams({
    this.B = 1.0,
    this.rho = 0.3,
    this.alphaA = 0.5,
    this.beta = 0.5,
    this.t = 0.5,
    this.bandThreshold = 0.15,
  });

  final double B;
  final double rho;
  final double alphaA;
  final double beta;
  final double t;
  final double bandThreshold;

  Map<String, num> toJson() => {
        'version': settlementVersion,
        'B': B,
        'rho': rho,
        'alphaA': alphaA,
        'beta': beta,
        't': t,
        'bandThreshold': bandThreshold,
      };
}
