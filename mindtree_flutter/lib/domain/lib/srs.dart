/// SM-2-ish spaced repetition state.
class SrsState {
  int interval;
  double ease;
  int reps;
  String dueAt;

  SrsState({required this.interval, required this.ease, required this.reps, required this.dueAt});

  factory SrsState.create() => SrsState(
        interval: 0,
        ease: 2.5,
        reps: 0,
        dueAt: DateTime.now().toIso8601String(),
      );

  Map<String, dynamic> toJson() => {
        'interval': interval,
        'ease': ease,
        'reps': reps,
        'dueAt': dueAt,
      };

  factory SrsState.fromJson(Map<String, dynamic> j) => SrsState(
        interval: (j['interval'] as num?)?.toInt() ?? 0,
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        dueAt: j['dueAt'] as String? ?? '',
      );
}

const double _minEase = 1.3;
const double _maxEase = 2.8;

/// SM-2 style scheduling:
/// correct: interval 1 -> 3 -> interval*ease; ease ±0.1 (clamp 1.3-2.8).
/// incorrect: interval reset to 0, ease -0.2.
SrsState scheduleReview(SrsState? prev, String quality) {
  final p = prev ?? SrsState.create();

  if (quality == 'incorrect' || quality == 'again') {
    return SrsState(
      interval: 0,
      ease: p.ease - 0.2 < _minEase ? _minEase : p.ease - 0.2,
      reps: 0,
      dueAt: DateTime.now().toIso8601String(),
    );
  }

  late int interval;
  if (p.reps == 0) {
    interval = 1;
  } else if (p.reps == 1) {
    interval = 3;
  } else {
    interval = (p.interval * p.ease).round();
  }

  final ease = p.ease + 0.1 > _maxEase ? _maxEase : p.ease + 0.1;
  final due = DateTime.now().add(Duration(days: interval));

  return SrsState(
    interval: interval,
    ease: ease,
    reps: p.reps + 1,
    dueAt: due.toIso8601String(),
  );
}

bool isDue(SrsState? state) {
  if (state == null) return true;
  final due = DateTime.tryParse(state.dueAt);
  if (due == null) return true;
  return due.millisecondsSinceEpoch <= DateTime.now().millisecondsSinceEpoch;
}

/// Approximate mastery: interval / 21, clamped 0..1.
double estimateMastery(SrsState? state) {
  if (state == null || state.reps == 0) return 0;
  final v = state.interval / 21;
  return v > 1 ? 1 : v;
}
