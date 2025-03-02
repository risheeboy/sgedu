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

  // Convert Game object to a map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'quizId': quizId,
      'hostId': hostId,
      'status': _gameStatusToString(status),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
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
    return Game(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      hostId: hostId ?? this.hostId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      players: players ?? Map.from(this.players),
      playerIds: playerIds ?? List.from(this.playerIds),
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

// Helper function to convert GameStatus enum to string
String _gameStatusToString(GameStatus status) {
  switch (status) {
    case GameStatus.waiting:
      return 'waiting';
    case GameStatus.inProgress:
      return 'inProgress';
    case GameStatus.completed:
      return 'completed';
  }
}
