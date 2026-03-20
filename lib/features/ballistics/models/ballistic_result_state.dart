import 'package:flutter/foundation.dart';

import 'package:monyx/features/ballistics/models/ballistic_solution.dart';

/// State for the ballistics UI.
@immutable
class BallisticResultState {
  const BallisticResultState({
    this.solution,
    this.isLoading = false,
    this.errorMessage,
    this.rangeCard = const [],
  });

  final BallisticSolution? solution;
  final bool isLoading;
  final String? errorMessage;
  final List<BallisticSolution> rangeCard;

  bool get hasResult => solution != null;
  bool get hasError => errorMessage != null;

  BallisticResultState copyWith({
    BallisticSolution? solution,
    bool? isLoading,
    String? errorMessage,
    List<BallisticSolution>? rangeCard,
    bool clearError = false,
    bool clearSolution = false,
  }) => BallisticResultState(
    solution: clearSolution ? null : solution ?? this.solution,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    rangeCard: rangeCard ?? this.rangeCard,
  );
}
