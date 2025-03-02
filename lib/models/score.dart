import 'package:cloud_firestore/cloud_firestore.dart';

enum ScoreStatus {
  pending,
  completed,
  error
}

extension ScoreStatusExtension on ScoreStatus {
  String get value {
    switch (this) {
      case ScoreStatus.pending:
        return 'pending';
      case ScoreStatus.completed:
        return 'completed';
      case ScoreStatus.error:
        return 'error';
    }
  }
  
  static ScoreStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return ScoreStatus.pending;
      case 'completed':
        return ScoreStatus.completed;
      case 'error':
        return ScoreStatus.error;
      default:
        return ScoreStatus.pending;
    }
  }
}

class Score {
  final String? id;
  final String gameId;
  final String questionId;
  final String userId;
  final String userAnswer;
  final String correctAnswer;
  final ScoreStatus status;
  final bool isCorrect;
  final String? feedback;
  final double? confidenceScore;
  final String? error;
  final Timestamp? timestamp;
  final Timestamp? processedAt;
  
  // MCQ specific fields
  final String? selectedOption;
  
  Score({
    this.id,
    required this.gameId,
    required this.questionId,
    required this.userId,
    required this.userAnswer,
    required this.correctAnswer,
    required this.status,
    required this.isCorrect,
    this.feedback,
    this.confidenceScore,
    this.error,
    this.timestamp,
    this.processedAt,
    this.selectedOption,
  });
  
  // Create from JSON (for deserializing API responses)
  factory Score.fromJson(Map<String, dynamic> json) {
    return Score(
      id: json['id'] as String?,
      gameId: json['gameId'] as String,
      questionId: json['questionId'] as String,
      userId: json['userId'] as String,
      userAnswer: json['userAnswer'] as String,
      correctAnswer: json['correctAnswer'] as String,
      status: ScoreStatusExtension.fromString(json['status'] as String),
      isCorrect: json['isCorrect'] as bool,
      feedback: json['feedback'] as String?,
      confidenceScore: json['confidenceScore'] as double?,
      error: json['error'] as String?,
      timestamp: json['timestamp'] as Timestamp?,
      processedAt: json['processedAt'] as Timestamp?,
      selectedOption: json['selectedOption'] as String?,
    );
  }
  
  // Create from Firestore document snapshot
  factory Score.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Score(
      id: doc.id,
      gameId: data['gameId'] as String,
      questionId: data['questionId'] as String,
      userId: data['userId'] as String,
      userAnswer: data['userAnswer'] as String,
      correctAnswer: data['correctAnswer'] as String,
      status: ScoreStatusExtension.fromString(data['status'] as String),
      isCorrect: data['isCorrect'] as bool? ?? false,
      feedback: data['feedback'] as String?,
      confidenceScore: data['confidenceScore'] as double?,
      error: data['error'] as String?,
      timestamp: data['timestamp'] as Timestamp?,
      processedAt: data['processedAt'] as Timestamp?,
      selectedOption: data['selectedOption'] as String?,
    );
  }
  
  // Convert to Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'gameId': gameId,
      'questionId': questionId,
      'userId': userId,
      'userAnswer': userAnswer,
      'correctAnswer': correctAnswer,
      'status': status.value,
      'isCorrect': isCorrect,
      if (feedback != null) 'feedback': feedback,
      if (confidenceScore != null) 'confidenceScore': confidenceScore,
      if (error != null) 'error': error,
      if (timestamp != null) 'timestamp': timestamp,
      if (processedAt != null) 'processedAt': processedAt,
      if (selectedOption != null) 'selectedOption': selectedOption,
    };
  }
  
  // Create a pending score
  factory Score.createPending({
    required String gameId,
    required String questionId,
    required String userId,
    required String userAnswer,
    required String correctAnswer,
    String? selectedOption,
  }) {
    return Score(
      gameId: gameId,
      questionId: questionId,
      userId: userId,
      userAnswer: userAnswer,
      correctAnswer: correctAnswer,
      status: ScoreStatus.pending,
      isCorrect: false, // Default until evaluated
      timestamp: Timestamp.now(),
      selectedOption: selectedOption,
    );
  }
  
  // Create a copy with updated fields
  Score copyWith({
    String? id,
    String? gameId,
    String? questionId,
    String? userId,
    String? userAnswer,
    String? correctAnswer,
    ScoreStatus? status,
    bool? isCorrect,
    String? feedback,
    double? confidenceScore,
    String? error,
    Timestamp? timestamp,
    Timestamp? processedAt,
    String? selectedOption,
  }) {
    return Score(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      questionId: questionId ?? this.questionId,
      userId: userId ?? this.userId,
      userAnswer: userAnswer ?? this.userAnswer,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      status: status ?? this.status,
      isCorrect: isCorrect ?? this.isCorrect,
      feedback: feedback ?? this.feedback,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
      processedAt: processedAt ?? this.processedAt,
      selectedOption: selectedOption ?? this.selectedOption,
    );
  }
}
