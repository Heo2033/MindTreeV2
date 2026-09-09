/// Type of an assessment.
enum AssessmentType {
  diagnostic,
  quiz,
  final_,
  milestone;

  static AssessmentType fromString(String? v) {
    switch (v) {
      case 'diagnostic':
        return AssessmentType.diagnostic;
      case 'quiz':
        return AssessmentType.quiz;
      case 'final':
        return AssessmentType.final_;
      case 'milestone':
        return AssessmentType.milestone;
      default:
        return AssessmentType.quiz;
    }
  }

  String get wire {
    switch (this) {
      case AssessmentType.diagnostic:
        return 'diagnostic';
      case AssessmentType.quiz:
        return 'quiz';
      case AssessmentType.final_:
        return 'final';
      case AssessmentType.milestone:
        return 'milestone';
    }
  }
}

/// Type of an assessment question.
enum QuestionType {
  recognition,
  recall,
  explanation,
  application,
  diagnosis,
  transfer;

  static QuestionType fromString(String? v) {
    switch (v) {
      case 'recognition':
        return QuestionType.recognition;
      case 'recall':
        return QuestionType.recall;
      case 'explanation':
        return QuestionType.explanation;
      case 'application':
        return QuestionType.application;
      case 'diagnosis':
        return QuestionType.diagnosis;
      case 'transfer':
        return QuestionType.transfer;
      default:
        return QuestionType.recognition;
    }
  }

  String get wire => name;
}

/// A single assessment question.
class AssessmentQuestion {
  final String id;
  final QuestionType type;
  final String nodeId;
  final String question;
  final List<String>? options;
  final String? correctAnswer;
  final String? explanation;

  const AssessmentQuestion({
    required this.id,
    this.type = QuestionType.recognition,
    required this.nodeId,
    required this.question,
    this.options,
    this.correctAnswer,
    this.explanation,
  });

  factory AssessmentQuestion.fromJson(Map<String, dynamic> json) => AssessmentQuestion(
        id: json['id'] as String,
        type: QuestionType.fromString(json['type'] as String?),
        nodeId: json['nodeId'] as String? ?? '',
        question: json['question'] as String,
        options: (json['options'] as List<dynamic>?)?.cast<String>(),
        correctAnswer: json['correctAnswer'] as String?,
        explanation: json['explanation'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'nodeId': nodeId,
        'question': question,
        if (options != null) 'options': options,
        if (correctAnswer != null) 'correctAnswer': correctAnswer,
        if (explanation != null) 'explanation': explanation,
      };
}

/// An assessment (test / quiz).
class Assessment {
  final String id;
  final String? sessionId;
  final AssessmentType type;
  final List<AssessmentQuestion> questions;
  final String startedAt;
  final String? completedAt;
  final double? score;

  const Assessment({
    required this.id,
    this.sessionId,
    this.type = AssessmentType.quiz,
    this.questions = const [],
    this.startedAt = '',
    this.completedAt,
    this.score,
  });

  factory Assessment.fromJson(Map<String, dynamic> json) => Assessment(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String?,
        type: AssessmentType.fromString(json['type'] as String?),
        questions: (json['questions'] as List<dynamic>? ?? [])
            .map((e) => AssessmentQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        startedAt: json['startedAt'] as String? ?? '',
        completedAt: json['completedAt'] as String?,
        score: (json['score'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'type': type.wire,
        'questions': questions.map((e) => e.toJson()).toList(),
        'startedAt': startedAt,
        'completedAt': completedAt,
        'score': score,
      };
}

/// A single attempt at answering an assessment question.
class Attempt {
  final String id;
  final String assessmentId;
  final String questionId;
  final String answer;
  final bool correct;
  final int timeSpentMs;
  final String? feedback;

  const Attempt({
    required this.id,
    required this.assessmentId,
    required this.questionId,
    required this.answer,
    this.correct = false,
    this.timeSpentMs = 0,
    this.feedback,
  });

  factory Attempt.fromJson(Map<String, dynamic> json) => Attempt(
        id: json['id'] as String,
        assessmentId: json['assessmentId'] as String,
        questionId: json['questionId'] as String,
        answer: json['answer'] as String,
        correct: json['correct'] as bool? ?? false,
        timeSpentMs: (json['timeSpentMs'] as num? ?? 0).toInt(),
        feedback: json['feedback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'assessmentId': assessmentId,
        'questionId': questionId,
        'answer': answer,
        'correct': correct,
        'timeSpentMs': timeSpentMs,
        if (feedback != null) 'feedback': feedback,
      };
}
