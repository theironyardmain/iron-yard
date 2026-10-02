import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';

/// Trainer records paired with their profile (brain.md §6.3).
typedef TrainerRecord = ({Profile profile, Trainer trainer});

/// Active trainers — what members see.
final activeTrainersProvider = StreamProvider<List<TrainerRecord>>(
  (ref) => ref.watch(profileDaoProvider).watchTrainers(),
);

/// Every trainer including retired ones, for admin management.
final allTrainersProvider = StreamProvider<List<TrainerRecord>>(
  (ref) => ref.watch(profileDaoProvider).watchTrainers(activeOnly: false),
);
