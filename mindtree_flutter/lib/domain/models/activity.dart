/// A step within a multi-step learning activity.
class ActivityStep {
  final String type; // explain | example | recall | apply
  final String title;
  final String? body;
  final String? instruction;
  final List<String>? options;
  final int? correctIndex;
  final String? bestAnswer;
  final String? placeholder;
  final String status; // pending | current | answered
  final String? userAnswer;
  final bool? correct;
  final String? feedback;

  const ActivityStep({
    required this.type,
    required this.title,
    this.body,
    this.instruction,
    this.options,
    this.correctIndex,
    this.bestAnswer,
    this.placeholder,
    this.status = 'pending',
    this.userAnswer,
    this.correct,
    this.feedback,
  });

  factory ActivityStep.fromJson(Map<String, dynamic> json) => ActivityStep(
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        instruction: json['instruction'] as String?,
        options: (json['options'] as List<dynamic>?)?.cast<String>(),
        correctIndex: (json['correctIndex'] as num?)?.toInt(),
        bestAnswer: json['bestAnswer'] as String?,
        placeholder: json['placeholder'] as String?,
        status: json['status'] as String? ?? 'pending',
        userAnswer: json['userAnswer'] as String?,
        correct: json['correct'] as bool?,
        feedback: json['feedback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        if (body != null) 'body': body,
        if (instruction != null) 'instruction': instruction,
        if (options != null) 'options': options,
        if (correctIndex != null) 'correctIndex': correctIndex,
        if (bestAnswer != null) 'bestAnswer': bestAnswer,
        if (placeholder != null) 'placeholder': placeholder,
        'status': status,
        if (userAnswer != null) 'userAnswer': userAnswer,
        if (correct != null) 'correct': correct,
        if (feedback != null) 'feedback': feedback,
      };

  bool get isAnswered => status == 'answered';
}

/// A four-step learning activity for a concept.
class LearningActivity {
  final String sessionId;
  final String itemId;
  final String nodeId;
  final String nodeLabel;
  final String goal;
  final List<ActivityStep> steps;
  final int currentStep;
  final bool isComplete;

  const LearningActivity({
    required this.sessionId,
    required this.itemId,
    required this.nodeId,
    required this.nodeLabel,
    required this.goal,
    this.steps = const [],
    this.currentStep = 0,
    this.isComplete = false,
  });

  factory LearningActivity.fromJson(Map<String, dynamic> json) => LearningActivity(
        sessionId: json['sessionId'] as String,
        itemId: json['itemId'] as String,
        nodeId: json['nodeId'] as String,
        nodeLabel: json['nodeLabel'] as String? ?? '',
        goal: json['goal'] as String? ?? 'overview',
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => ActivityStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentStep: (json['currentStep'] as num? ?? 0).toInt(),
        isComplete: json['isComplete'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'itemId': itemId,
        'nodeId': nodeId,
        'nodeLabel': nodeLabel,
        'goal': goal,
        'steps': steps.map((e) => e.toJson()).toList(),
        'currentStep': currentStep,
        'isComplete': isComplete,
      };

  LearningActivity copyWith({
    List<ActivityStep>? steps,
    int? currentStep,
    bool? isComplete,
  }) =>
      LearningActivity(
        sessionId: sessionId,
        itemId: itemId,
        nodeId: nodeId,
        nodeLabel: nodeLabel,
        goal: goal,
        steps: steps ?? this.steps,
        currentStep: currentStep ?? this.currentStep,
        isComplete: isComplete ?? this.isComplete,
      );
}
