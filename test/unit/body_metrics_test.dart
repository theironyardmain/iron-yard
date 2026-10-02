import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/utils/body_metrics.dart';

void main() {
  group('bmi', () {
    test('computes a normal-range value', () {
      // 70kg at 175cm -> ~22.9.
      final bmi = BodyMetrics.bmi(weightKg: 70, heightCm: 175);
      expect(bmi, closeTo(22.86, 0.01));
    });

    test('is null when weight is missing', () {
      expect(BodyMetrics.bmi(weightKg: null, heightCm: 175), isNull);
    });

    test('is null when height is missing', () {
      expect(BodyMetrics.bmi(weightKg: 70, heightCm: null), isNull);
    });

    test('is null for non-positive inputs', () {
      expect(BodyMetrics.bmi(weightKg: 0, heightCm: 175), isNull);
      expect(BodyMetrics.bmi(weightKg: 70, heightCm: 0), isNull);
      expect(BodyMetrics.bmi(weightKg: -5, heightCm: 175), isNull);
    });
  });

  group('bmiCategory', () {
    test('classifies the standard WHO bands', () {
      expect(BodyMetrics.bmiCategory(17), 'Underweight');
      expect(BodyMetrics.bmiCategory(22), 'Normal');
      expect(BodyMetrics.bmiCategory(27), 'Overweight');
      expect(BodyMetrics.bmiCategory(32), 'Obese');
    });

    test('boundaries belong to the higher band', () {
      expect(BodyMetrics.bmiCategory(18.5), 'Normal');
      expect(BodyMetrics.bmiCategory(25), 'Overweight');
      expect(BodyMetrics.bmiCategory(30), 'Obese');
    });
  });

  group('ageFrom', () {
    test('computes whole years when the birthday has passed this year', () {
      final age = BodyMetrics.ageFrom(
        DateTime(2000, 3, 1),
        asOf: DateTime(2026, 6, 15),
      );
      expect(age, 26);
    });

    test('has not had the birthday yet this year', () {
      final age = BodyMetrics.ageFrom(
        DateTime(2000, 12, 1),
        asOf: DateTime(2026, 6, 15),
      );
      expect(age, 25);
    });

    test('the exact birthday counts as having had it', () {
      final age = BodyMetrics.ageFrom(
        DateTime(2000, 6, 15),
        asOf: DateTime(2026, 6, 15),
      );
      expect(age, 26);
    });

    test('is null without a date of birth', () {
      expect(BodyMetrics.ageFrom(null), isNull);
    });
  });

  group('basalMetabolicRate', () {
    test('male formula', () {
      // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780.
      final bmr = BodyMetrics.basalMetabolicRate(
        weightKg: 80,
        heightCm: 180,
        ageYears: 30,
        gender: 'Male',
      );
      expect(bmr, 1780);
    });

    test('female formula', () {
      // 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25.
      final bmr = BodyMetrics.basalMetabolicRate(
        weightKg: 60,
        heightCm: 165,
        ageYears: 25,
        gender: 'Female',
      );
      expect(bmr, closeTo(1345.25, 0.01));
    });

    test('averages the two sex terms for other/unspecified gender', () {
      final other = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'Other',
      );
      final male = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'Male',
      );
      final female = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'Female',
      );
      expect(other, closeTo((male! + female!) / 2, 0.001));
    });

    test('treats a null gender the same as other/unspecified', () {
      final nullGender = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: null,
      );
      final other = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'Other',
      );
      expect(nullGender, other);
    });

    test('is case-insensitive', () {
      final lower = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'male',
      );
      final mixed = BodyMetrics.basalMetabolicRate(
        weightKg: 70,
        heightCm: 170,
        ageYears: 28,
        gender: 'Male',
      );
      expect(lower, mixed);
    });

    test('is null when any required input is missing', () {
      expect(
        BodyMetrics.basalMetabolicRate(
          weightKg: null,
          heightCm: 170,
          ageYears: 28,
          gender: 'male',
        ),
        isNull,
      );
      expect(
        BodyMetrics.basalMetabolicRate(
          weightKg: 70,
          heightCm: null,
          ageYears: 28,
          gender: 'male',
        ),
        isNull,
      );
      expect(
        BodyMetrics.basalMetabolicRate(
          weightKg: 70,
          heightCm: 170,
          ageYears: null,
          gender: 'male',
        ),
        isNull,
      );
    });
  });

  group('dailyCalorieTarget', () {
    test('multiplies BMR by the activity level and rounds to the nearest 10',
        () {
      // BMR = 1780 (see male formula test above).
      final target = BodyMetrics.dailyCalorieTarget(
        weightKg: 80,
        heightCm: 180,
        ageYears: 30,
        gender: 'male',
        activityLevel: ActivityLevel.sedentary,
      );
      // 1780 * 1.2 = 2136 -> rounds to 2140.
      expect(target, 2140);
    });

    test('one value per activity level, strictly increasing', () {
      final targets = [
        for (final level in ActivityLevel.values)
          BodyMetrics.dailyCalorieTarget(
            weightKg: 75,
            heightCm: 175,
            ageYears: 30,
            gender: 'male',
            activityLevel: level,
          )!,
      ];

      for (var i = 1; i < targets.length; i++) {
        expect(targets[i], greaterThan(targets[i - 1]));
      }
    });

    test('is null when the underlying BMR cannot be computed', () {
      expect(
        BodyMetrics.dailyCalorieTarget(
          weightKg: null,
          heightCm: 175,
          ageYears: 30,
          gender: 'male',
          activityLevel: ActivityLevel.moderate,
        ),
        isNull,
      );
    });
  });

  group('activityMultiplierFor', () {
    test('matches the standard multipliers', () {
      expect(BodyMetrics.activityMultiplierFor(ActivityLevel.sedentary), 1.2);
      expect(BodyMetrics.activityMultiplierFor(ActivityLevel.light), 1.375);
      expect(BodyMetrics.activityMultiplierFor(ActivityLevel.moderate), 1.55);
      expect(BodyMetrics.activityMultiplierFor(ActivityLevel.active), 1.725);
    });
  });

  group('targetLoadKg', () {
    test('computes the percentage of bodyweight', () {
      expect(
        BodyMetrics.targetLoadKg(bodyweightPercent: 50, weightKg: 80),
        40,
      );
    });

    test('is null when bodyweightPercent is missing', () {
      expect(
        BodyMetrics.targetLoadKg(bodyweightPercent: null, weightKg: 80),
        isNull,
      );
    });

    test('is null when weight is missing', () {
      expect(
        BodyMetrics.targetLoadKg(bodyweightPercent: 50, weightKg: null),
        isNull,
      );
    });

    test('handles over 100%', () {
      expect(
        BodyMetrics.targetLoadKg(bodyweightPercent: 150, weightKg: 80),
        120,
      );
    });
  });

  group('ActivityLevel', () {
    test('fromString round-trips wireValue', () {
      for (final level in ActivityLevel.values) {
        expect(ActivityLevel.fromString(level.wireValue), level);
      }
    });

    test('fromString returns null for an unknown value', () {
      expect(ActivityLevel.fromString('extreme'), isNull);
      expect(ActivityLevel.fromString(null), isNull);
    });
  });
}
