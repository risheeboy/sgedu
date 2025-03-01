import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/game.dart';
import '../models/quiz.dart';
import 'quiz_service.dart';

class GameService {
  final CollectionReference _games = FirebaseFirestore.instance.collection('games');
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final QuizService _quizService = QuizService();

  // Get a list of available public games
  Stream<List<Game>> getPublicGamesStream() {
    return _games
        .where('isPublic', isEqualTo: true)
        .where('status', isEqualTo: 'waiting')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Game.fromFirestore(doc))
            .toList());
  }

  // Get games that a user is currently participating in
  Stream<List<Game>> getUserGamesStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    // Use array-contains query on player IDs instead of map field query
    final String userId = user.uid;
    return _games
        .where('playerIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Game.fromFirestore(doc))
            .toList());
  }

  // Get a specific game by ID
  Stream<Game?> getGameStream(String gameId) {
    return _games
        .doc(gameId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? Game.fromFirestore(snapshot) : null);
  }

  // Create a new game
  Future<String> createGame({
    required String quizId,
    bool isPublic = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to create a game');
    }

    // Create a new document reference to get the ID
    final docRef = _games.doc();
    
    final game = Game(
      id: docRef.id,
      quizId: quizId,
      hostId: user.uid,
      status: GameStatus.waiting,
      createdAt: DateTime.now(),
      players: {user.uid: user.displayName ?? 'Host'},
      isPublic: isPublic,
    );

    await docRef.set(game.toFirestore());
    return docRef.id;
  }

  // Join an existing game
  Future<void> joinGame(String gameId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to join a game');
    }

    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // Check if game is in waiting state
    if (game.status != GameStatus.waiting) {
      throw Exception('Game has already started or is completed');
    }

    // Check if user is already in the game
    if (game.players.containsKey(user.uid)) {
      print('User is already in the game, nothing to do');
      return;
    }

    print('playerIds: ${game.playerIds} Joining game: $gameId');
    // Add user to players map and playerIds array
    await _games.doc(gameId).update({
      'players.${user.uid}': user.displayName ?? 'Player',
      'playerIds': FieldValue.arrayUnion([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Leave a game
  Future<void> leaveGame(String gameId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to leave a game');
    }

    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // If user is the host, cancel the game if it's still in waiting state
    if (game.hostId == user.uid && game.status == GameStatus.waiting) {
      await _games.doc(gameId).delete();
      return;
    }

    // Otherwise just remove the user from the players list and playerIds array
    final playersCopy = Map<String, String>.from(game.players);
    playersCopy.remove(user.uid);

    await _games.doc(gameId).update({
      'players': playersCopy,
      'playerIds': FieldValue.arrayRemove([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Start a game (host only)
  Future<void> startGame(String gameId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to start a game');
    }

    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // Only host can start the game
    if (game.hostId != user.uid) {
      throw Exception('Only the host can start the game');
    }

    // Check if game is in waiting state
    if (game.status != GameStatus.waiting) {
      throw Exception('Game has already started or is completed');
    }


    // Update game status to in progress
    await _games.doc(gameId).update({
      'status': 'inProgress',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Move to next question (host only)
  Future<void> nextQuestion(String gameId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to advance the game');
    }

    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // Only host can advance the game
    if (game.hostId != user.uid) {
      throw Exception('Only the host can advance the game');
    }

    // Check if game is in progress
    if (game.status != GameStatus.inProgress) {
      throw Exception('Game is not in progress');
    }

    // Get quiz to check number of questions
    final quizDoc = await FirebaseFirestore.instance
        .collection('quizzes')
        .doc(game.quizId)
        .get();
    
    if (!quizDoc.exists) {
      throw Exception('Quiz not found');
    }

    final quiz = Quiz.fromFirestore(quizDoc);
    final newIndex = game.currentQuestionIndex + 1;
    
    // If this was the last question, mark the game as completed
    if (newIndex >= quiz.questionIds.length) {
      await _games.doc(gameId).update({
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Otherwise, move to the next question
      await _games.doc(gameId).update({
        'currentQuestionIndex': newIndex,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Submit an answer for a question
  Future<void> submitAnswer({
    required String gameId,
    required String questionId,
    required String answer,
    required bool isCorrect,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to submit an answer');
    }

    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // Check if game is in progress
    if (game.status != GameStatus.inProgress) {
      throw Exception('Game is not in progress');
    }

    // Check if user is a player
    if (!game.players.containsKey(user.uid)) {
      throw Exception('You are not a player in this game');
    }

    // Calculate score (could be more sophisticated based on time, etc.)
    final score = isCorrect ? 10 : 0;

    // Create a new score document
    final scoreData = GameScore(
      gameId: gameId,
      userId: user.uid,
      questionId: questionId,
      isCorrect: isCorrect,
      score: score,
      userAnswer: answer,
      submittedAt: DateTime.now(),
    );

    // Add to scores subcollection
    await _games
        .doc(gameId)
        .collection('scores')
        .add(scoreData.toFirestore());
  }

  // Get scores for a game
  Stream<List<GameScore>> getGameScoresStream(String gameId) {
    return _games
        .doc(gameId)
        .collection('scores')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GameScore.fromFirestore(doc))
            .toList());
  }

  // Get user scores for a specific game
  Stream<List<GameScore>> getUserGameScoresStream(String gameId, String userId) {
    return _games
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GameScore.fromFirestore(doc))
            .toList());
  }

  // Get current question for a game
  Future<String?> getCurrentQuestionId(String gameId) async {
    final gameDoc = await _games.doc(gameId).get();
    if (!gameDoc.exists) {
      throw Exception('Game not found');
    }

    final game = Game.fromFirestore(gameDoc);
    
    // Get the quiz
    final quizDoc = await FirebaseFirestore.instance
        .collection('quizzes')
        .doc(game.quizId)
        .get();
    
    if (!quizDoc.exists) {
      throw Exception('Quiz not found');
    }

    final quiz = Quiz.fromFirestore(quizDoc);
    
    // Make sure the index is valid
    if (game.currentQuestionIndex < 0 || game.currentQuestionIndex >= quiz.questionIds.length) {
      return null;
    }
    
    return quiz.questionIds[game.currentQuestionIndex];
  }

  // Get a leaderboard of scores for a game
  Future<Map<String, int>> getGameLeaderboard(String gameId) async {
    final scoresSnapshot = await _games
        .doc(gameId)
        .collection('scores')
        .get();
    
    // Group scores by user ID and sum them
    final scoresByUser = <String, int>{};
    
    for (final doc in scoresSnapshot.docs) {
      final score = GameScore.fromFirestore(doc);
      scoresByUser[score.userId] = (scoresByUser[score.userId] ?? 0) + score.score;
    }
    
    return scoresByUser;
  }
}
