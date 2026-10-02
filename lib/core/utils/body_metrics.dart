/// BMI, calorie targets, and bodyweight-relative loads (brain.md §6.11).
///
/// Pure functions only — no database or Flutter dependency — so this stays
/// unit-testable without a Drift instance.
class BodyMetrics {
  const BodyMetrics._();

  /// BMI = kg / (m)^2. Null if either input is missing or non-positive.
  static double? bmi({required double? weightKg, required int? heightCm}) {
    if (weightKg == null || heightCm == null) return null;
    if (weightKg <= 0 || heightCm <= 0) return null;

    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// The standard WHO BMI bands.
  static String bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  /// Whole years of age from a date of birth, as of [asOf] (defaults to now).
  /// Null if [dateOfBirth] is null.
  static int? ageFrom(DateTime? dateOfBirth, {DateTime? asOf}) {
    if (dateOfBirth == null) return null;
    final today = asOf ?? DateTime.now();

    var age = today.year - dateOfBirth.year;
    final hadBirthdayThisYear =
        today.month > dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day >= dateOfBirth.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age;
  }

  /// Mifflin-St Jeor basal metabolic rate, in kcal/day.
  ///
  /// The formula's sex term only captures a population-average lean-mass
  /// difference: for a [gender] that is not clearly 'male' or 'female', the
  /// two variants are averaged rather than forcing a blocking choice (brain.md
  /// §6.11). Null if any of [weightKg]/[heightCm]/[ageYears] is missing.
  static double? basalMetabolicRate({
    required double? weightKg,
    required int? heightCm,
    required int? ageYears,
    required String? gender,
  }) {
    if (weightKg == null || heightCm == null || ageYears == null) return null;

    final base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
    final sexTerm = switch (gender?.toLowerCase()) {
      'male' => 5,
      'female' => -161,
      _ => (5 + -161) / 2, // averaged for other/unspecified — see doc comment
    };
    return base + sexTerm;
  }

  static double activityMultiplierFor(ActivityLevel level) => switch (level) {
    ActivityLevel.sedentary => 1.2,
    ActivityLevel.light => 1.375,
    ActivityLevel.moderate => 1.55,
    ActivityLevel.active => 1.725,
  };

  /// Suggested daily calorie target: BMR × activity multiplier, rounded to
  /// the nearest 10 kcal (single-calorie precision would be false precision).
  /// Null if [basalMetabolicRate] cannot be computed.
  static int? dailyCalorieTarget({
    required double? weightKg,
    required int? heightCm,
    required int? ageYears,
    required String? gender,
    required ActivityLevel activityLevel,
  }) {
    final bmr = basalMetabolicRate(
      weightKg: weightKg,
      heightCm: heightCm,
      ageYears: ageYears,
      gender: gender,
    );
    if (bmr == null) return null;

    final target = bmr * activityMultiplierFor(activityLevel);
    return (target / 10).round() * 10;
  }

  /// The actual target load for a bodyweight-relative exercise, e.g. 50% of
  /// 80kg -> 40.0. Null if either input is missing.
  static double? targetLoadKg({
    required double? bodyweightPercent,
    required double? weightKg,
  }) {
    if (bodyweightPercent == null || weightKg == null) return null;
    return weightKg * bodyweightPercent / 100;
  }
}

/// Activity multipliers for the Mifflin-St Jeor calorie target (brain.md §6.11).
enum ActivityLevel {
  sedentary,
  light,
  moderate,
  active;

  static ActivityLevel? fromString(String? value) => switch (value) {
    'sedentary' => ActivityLevel.sedentary,
    'light' => ActivityLevel.light,
    'moderate' => ActivityLevel.moderate,
    'active' => ActivityLevel.active,
    _ => null,
  };

  String get wireValue => name;

  String get label => switch (this) {
    ActivityLevel.sedentary => 'Sedentary',
    ActivityLevel.light => 'Light activity',
    ActivityLevel.moderate => 'Moderate activity',
    ActivityLevel.active => 'Very active',
  };
}
