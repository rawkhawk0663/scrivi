/// Bruchzahl für Notenlängen und Zeitpunkte im Takt (1/4 = eine Viertelnote).
/// Rechnet genau, damit sich Triolen und Punktierungen nie verrunden.
class Fraction implements Comparable<Fraction> {
  factory Fraction(int numerator, [int denominator = 1]) {
    if (denominator == 0) throw ArgumentError('Nenner 0');
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final g = _gcd(numerator.abs(), denominator);
    return Fraction._(numerator ~/ (g == 0 ? 1 : g), denominator ~/ (g == 0 ? 1 : g));
  }
  const Fraction._(this.n, this.d);

  static const zero = Fraction._(0, 1);

  final int n;
  final int d;

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a;
  }

  Fraction operator +(Fraction o) => Fraction(n * o.d + o.n * d, d * o.d);
  Fraction operator -(Fraction o) => Fraction(n * o.d - o.n * d, d * o.d);
  Fraction operator *(Fraction o) => Fraction(n * o.n, d * o.d);
  Fraction operator /(Fraction o) => Fraction(n * o.d, d * o.n);
  Fraction scale(int numerator, [int denominator = 1]) => Fraction(n * numerator, d * denominator);

  bool operator <(Fraction o) => compareTo(o) < 0;
  bool operator <=(Fraction o) => compareTo(o) <= 0;
  bool operator >(Fraction o) => compareTo(o) > 0;
  bool operator >=(Fraction o) => compareTo(o) >= 0;

  bool get isZero => n == 0;
  double toDouble() => n / d;

  @override
  int compareTo(Fraction o) => (n * o.d).compareTo(o.n * d);

  @override
  bool operator ==(Object other) => other is Fraction && other.n == n && other.d == d;

  @override
  int get hashCode => Object.hash(n, d);

  @override
  String toString() => d == 1 ? '$n' : '$n/$d';
}
