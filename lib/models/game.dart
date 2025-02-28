import 'package:cloud_firestore/cloud_firestore.dart';

// Status of a game session
enum GameStatus {
  waiting,  // Waiting for players to join
  inProgress, // Game is in progress
  completed, // Game is over
}

class Game {
  final String id;
  final String quizId;
  final String hostId;
  final GameStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, String> players; // Map of user IDs to display names
  final List<String> playerIds; // List of player IDs for querying
  final int currentQuestionIndex;
  final bool isPublic; // Whether anyone can join or by invitation only

  Game({
    required this.id,
    required this.quizId,
    required this.hostId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    required this.players,
    List<String>? playerIds,
    this.currentQuestionIndex = 0,
    this.isPublic = true,
  }) : playerIds = playerIds ?? players.keys.toList();

  // Convert Firestore document to Game object
  factory Game.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final players = Map<String, String>.from(data['players'] ?? {});
    
    return Game(
      id: doc.id,
      quizId: data['quizId'] ?? '',
      hostId: data['hostId'] ?? '',
      status: _gameStatusFromString(data['status'] ?? 'waiting'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      players: players,
      playerIds: (data['playerIds'] as List<dynamic>?)?.cast<String>() ?? players.keys.toList(),
      currentQuestionIndex: data['currentQuestionIndex'] ?? 0,
      isPublic: data['isPublic'] ?? true,
    );
  }

  // Convert Game object to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'quizId': quizId,
      'hostId': hostId,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'players': players,
      'playerIds': playerIds,
      'currentQuestionIndex': currentQuestionIndex,
      'isPublic': isPublic,
    };
  }

  // Create a copy of the Game with updated fields
  Game copyWith({
    String? id,
    String? quizId,
    String? hostId,
    GameStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, String>? players,
    List<String>? playerIds,
    int? currentQuestionIndex,
    bool? isPublic,
  }) {
    final updatedPlayers = players ?? Map<String, String>.from(this.players);
    
    return Game(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      hostId: hostId ?? this.hostId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      players: updatedPlayers,
      playerIds: playerIds ?? (players != null ? updatedPlayers.keys.toList() : this.playerIds),
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isPublic: isPublic ?? this.isPublic,
    );
  }
}

// Helper function to convert string to GameStatus enum
GameStatus _gameStatusFromString(String status) {
  switch (status) {
    case 'waiting':
      return GameStatus.waiting;
    case 'inProgress':
      return GameStatus.inProgress;
    case 'completed':
      return GameStatus.completed;
    default:
      return GameStatus.waiting;
  }
}

// Class to represent a player's score in a game
class GameScore {
  final String gameId;
  final String userId;
  final String questionId;
  final bool isCorrect;
  final int score;
  final String userAnswer;
  final DateTime submittedAt;

  GameScore({
    required this.gameId,
    required this.userId,
    required this.questionId,
    required this.isCorrect,
    required this.score,
    required this.userAnswer,
    required this.submittedAt,
  });

  // Convert Firestore document to GameScore object
  factory GameScore.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GameScore(
      gameId: data['gameId'] ?? '',
      userId: data['userId'] ?? '',
      questionId: data['questionId'] ?? '',
      isCorrect: data['isCorrect'] ?? false,
      score: data['score'] ?? 0,
      userAnswer: data['userAnswer'] ?? '',
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Convert GameScore object to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'gameId': gameId,
      'userId': userId,
      'questionId': questionId,
      'isCorrect': isCorrect,
      'score': score,
      'userAnswer': userAnswer,
      'submittedAt': Timestamp.fromDate(submittedAt),
    };
  }
}
