import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/game.dart';
import '../models/quiz.dart';
import '../models/question.dart';
import '../models/score.dart';
import '../services/score_service.dart';
import 'quiz_service.dart';

class GameService {
  final CollectionReference _games = FirebaseFirestore.instance.collection('games');
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final QuizService _quizService = QuizService();
  final ScoreService _scoreService = ScoreService();

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

  // Register a player's score with question details
  Future<void> registerPlayerScore(String gameId, String userId, int score, String questionId) async {
    try {
      final questionDoc = await getQuestion(questionId);
      if (questionDoc.id == null) {
        throw Exception('Question not found');
      }
      
      // Use the current user's answer if available (for MCQ questions)
      // This is a simplified version - in a real implementation, you'd pass the actual user answer
      final userAnswer = ""; // Placeholder for MCQ selection or text answer
      final isCorrect = score > 0; // If score is positive, answer is correct
      
      // Create a score document using the Score model
      final scoreDoc = Score.createCompleted(
        gameId: gameId,
        questionId: questionId,
        userId: userId,
        userAnswer: userAnswer,
        correctAnswer: questionDoc.correctAnswer,
        isCorrect: isCorrect,
        score: score,
      );
      
      // Add to scores subcollection
      await _games
          .doc(gameId)
          .collection('scores')
          .add(scoreDoc.toFirestore());
      
      print('Successfully registered score $score for player $userId on question $questionId');
    } catch (e) {
      print('Error registering player score: $e');
    }
  }

  // Get a question by ID
  Future<Question> getQuestion(String questionId) async {
    try {
      final questionDoc = await FirebaseFirestore.instance
          .collection('questions')
          .doc(questionId)
          .get();
      
      if (!questionDoc.exists) {
        throw Exception('Question not found');
      }
      
      return Question.fromFirestore(questionDoc);
    } catch (e) {
      print('Error getting question: $e');
      throw Exception('Failed to load question: $e');
    }
  }

  // Get scores for a game
  Stream<List<Score>> getGameScoresStream(String gameId) {
    return _games
        .doc(gameId)
        .collection('scores')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Score.fromFirestore(doc))
            .toList());
  }

  // Get user scores for a specific game
  Stream<List<Score>> getUserGameScoresStream(String gameId, String userId) {
    return _games
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Score.fromFirestore(doc))
            .toList());
  }

  // Get the current question for a game
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
    try {
      print('Getting leaderboard for game: $gameId');
      
      // Get all score documents
      final scoresSnapshot = await _games
          .doc(gameId)
          .collection('scores')
          .where('status', isEqualTo: 'completed')
          .get();
      
      print('Found ${scoresSnapshot.docs.length} score documents');
      
      // Group scores by user ID
      final scoresByUser = <String, int>{};
      
      for (final doc in scoresSnapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String;
        final questionId = data['questionId'] as String;
        
        // Use the score field directly from the document
        final score = data['score'] as int? ?? 0;
        
        print('User: $userId, Question: $questionId, Score: $score');
        
        // Add the score to the user's total
        scoresByUser[userId] = (scoresByUser[userId] ?? 0) + score;
      }
      
      print('Aggregated scores by user: $scoresByUser');
      return scoresByUser;
    } catch (e) {
      print('Error getting game leaderboard: $e');
      return {};
    }
  }

  // Increment a player's score by the specified amount
  Future<void> incrementScore(String gameId, String userId, int points, {required String questionId}) async {
    try {
      await _scoreService.incrementScore(gameId, userId, points, questionId);
      print('Incremented score for user $userId by $points points');
    } catch (e) {
      print('Error incrementing score: $e');
      throw Exception('Failed to update score: $e');
    }
  }
}
