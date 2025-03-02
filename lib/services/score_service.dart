import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/score.dart';
import '../models/question.dart';

class ScoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Submit an answer for scoring
  Future<DocumentReference> submitAnswer({
    required String gameId,
    required Question question,
    required String userAnswer,
    String? selectedOption,
    bool? isCorrect,  // For local MCQ evaluation
    ScoreStatus? status,  // For setting pre-evaluated status
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to submit answers');
    }
    
    // For MCQ questions that are evaluated locally
    if (isCorrect != null && status != null) {
      // Create a score with the known evaluation result
      final score = Score(
        gameId: gameId,
        questionId: question.id!,
        userId: user.uid,
        userAnswer: userAnswer,
        correctAnswer: question.correctAnswer,
        selectedOption: selectedOption,
        status: status,
        isCorrect: isCorrect,
        feedback: isCorrect ? 'Correct!' : 'Incorrect. The correct answer is: ${question.correctAnswer}',
        timestamp: Timestamp.now(),
        processedAt: Timestamp.now(),
      );
      
      return await _firestore
          .collection('games')
          .doc(gameId)
          .collection('scores')
          .doc(user.uid)
          .set(score.toFirestore(), SetOptions(merge: true))
          .then((_) => _firestore.collection('games').doc(gameId).collection('scores').doc(user.uid));
    } else {
      // Create a pending score for AI evaluation
      final score = Score.createPending(
        gameId: gameId,
        questionId: question.id!,
        userId: user.uid,
        userAnswer: userAnswer,
        correctAnswer: question.correctAnswer,
        selectedOption: selectedOption,
      );
      
      return await _firestore
          .collection('games')
          .doc(gameId)
          .collection('scores')
          .add(score.toFirestore());
    }
  }
  
  // Get a stream of updates for a specific score
  Stream<Score> getScoreStream(String gameId, String scoreId) {
    return _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .doc(scoreId)
        .snapshots()
        .map((snapshot) => Score.fromFirestore(snapshot));
  }
  
  // Get all scores for a game
  Stream<List<Score>> getGameScoresStream(String gameId) {
    return _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Score.fromFirestore(doc))
            .toList());
  }
  
  // Get the most recent score for a user and question
  Future<Score?> getUserQuestionScore(String gameId, String questionId, String userId) async {
    final snapshot = await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .where('questionId', isEqualTo: questionId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
        
    if (snapshot.docs.isEmpty) {
      return null;
    }
    
    return Score.fromFirestore(snapshot.docs.first);
  }
  
  // Get all scores for a user in a game
  Stream<List<Score>> getUserGameScoresStream(String gameId, String userId) {
    return _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => 
            snapshot.docs.map((doc) => Score.fromFirestore(doc)).toList());
  }
  
  // Get a user's total score in a game
  Future<int> getUserGameScore(String gameId, String userId) async {
    final scoreSnapshot = await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .doc(userId)
        .get();
    
    if (!scoreSnapshot.exists) {
      return 0;
    }
    
    final data = scoreSnapshot.data();
    return (data?['score'] as num?)?.toInt() ?? 0;
  }
  
  // Increment a player's score
  Future<void> incrementScore(String gameId, String userId, int points) async {
    await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .doc(userId)
        .set({
          'score': FieldValue.increment(points),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
