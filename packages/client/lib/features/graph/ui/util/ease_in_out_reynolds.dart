import 'dart:math';
import 'package:flutter/animation.dart';

class EaseInOutReynolds extends Curve {
  /// An animation easing function that adapts linear animation to human perception.
  ///
  /// This function is based on the work of Maverick Reynolds, "A New Family of Easing Functions".
  /// The function idea is derived from slightly modifying the logistic equation
  /// to "ramp up" at the end: dR/dt = kR(1-R) / t(1-t)
  ///
  /// The `calculateInOutReynolds` function takes in three parameters:
  // ignore: comment_references
  /// * [t] which is the current value of the animation. It should be a value between 0 and 1.
  /// * [skewFactor] which is used to skew the speed-up towards the start or the end. If it's less than 1,
  /// speed-up is towards the start, if it's more than 1, speed-up is towards the end.
  /// * [nonlinearity] which is the degree of speeding-up in the middle (non-linearity).

  final double skewFactor;
  final double nonlinearity;

  const EaseInOutReynolds({this.skewFactor = 1, this.nonlinearity = 2});

  @override
  double transformInternal(double t) =>
      1 / (1 + skewFactor * pow(1 / t - 1, nonlinearity));
}
