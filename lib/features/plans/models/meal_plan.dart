import 'dart:convert';

/// One meal in a diet plan (brain.md §6.6).
class Meal {
  const Meal({required this.name, required this.items});

  final String name;
  final List<String> items;

  Map<String, Object?> toJson() => {'meal': name, 'items': items};

  static Meal? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final name = json['meal'];
    if (name is! String || name.isEmpty) return null;

    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems.whereType<String>().toList()
        : <String>[];

    return Meal(name: name, items: items);
  }
}

/// Encodes and decodes the meal list stored in `diet_plans.meals_json`.
///
/// Diet plans are read-only content rather than something queried field by
/// field, so they live as JSON instead of a nested table.
class MealPlan {
  const MealPlan._();

  static String? encode(List<Meal> meals) =>
      meals.isEmpty ? null : jsonEncode(meals.map((m) => m.toJson()).toList());

  /// Decodes stored JSON, tolerating null and malformed content.
  ///
  /// A plan written by an older version, or corrupted in transit, should show
  /// as empty rather than crashing the member's plan screen.
  static List<Meal> decode(String? json) {
    if (json == null || json.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }

    if (decoded is! List) return const [];

    return decoded.map(Meal.fromJson).whereType<Meal>().toList(growable: false);
  }
}
