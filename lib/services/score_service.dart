import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/score.dart';
import '../models/question.dart';

class ScoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Submit an answer for scoring - consolidated function for MCQ and non-MCQ questions
  Future<DocumentReference> submitAnswer({
    required String gameId,
    required Question question,
    required String userAnswer,
    String? selectedOption,
    bool? isCorrect,  // For local MCQ evaluation
    int? score,      // Score value (0, 1 for MCQ, 0-2 for non-MCQ)
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to submit answers');
    }
    
    // For MCQ questions that are evaluated locally
    if (isCorrect != null && score != null) {
      // Create a completed score with the known evaluation result
      final scoreDoc = Score.createCompleted(
        gameId: gameId,
        questionId: question.id!,
        userId: user.uid,
        userAnswer: userAnswer,
        correctAnswer: question.correctAnswer,
        isCorrect: isCorrect,
        score: score,
        selectedOption: selectedOption,
      );
      
      // Add a new document with a unique ID for each answer
      return await _firestore
          .collection('games')
          .doc(gameId)
          .collection('scores')
          .add(scoreDoc.toFirestore());
    } else {
      // Create a pending score for AI evaluation
      final scoreDoc = Score.createPending(
        gameId: gameId,
        questionId: question.id!,
        userId: user.uid,
        userAnswer: userAnswer,
        correctAnswer: question.correctAnswer,
        selectedOption: selectedOption,
      );
      
      // Add score document with pending status for cloud function to evaluate
      return await _firestore
          .collection('games')
          .doc(gameId)
          .collection('scores')
          .add(scoreDoc.toFirestore());
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
  
  // Get a specific score document by question ID for a user
  Future<Score?> getUserQuestionScoreDoc(String gameId, String userId, String questionId) async {
    final snapshot = await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .where('questionId', isEqualTo: questionId)
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
  
  // Get a user's total score in a game by summing all score documents
  Future<int> getUserGameScore(String gameId, String userId) async {
    final scoresSnapshot = await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .get();
    
    // Sum up all scores for this user
    int totalScore = 0;
    for (var doc in scoresSnapshot.docs) {
      totalScore += (doc.data()['score'] as num?)?.toInt() ?? 0;
    }
    
    return totalScore;
  }
  
  // Get a user's score for a specific question in a game
  Future<int> getUserQuestionScore(String gameId, String userId, String questionId) async {
    final scoresSnapshot = await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .where('userId', isEqualTo: userId)
        .where('questionId', isEqualTo: questionId)
        .get();
    
    // Sum up all scores for this user and question
    int totalScore = 0;
    for (var doc in scoresSnapshot.docs) {
      totalScore += (doc.data()['score'] as num?)?.toInt() ?? 0;
    }
    
    return totalScore;
  }
  
  // Add points to a user's score by creating a new score document
  Future<void> incrementScore(String gameId, String userId, int points, String questionId) async {
    await _firestore
        .collection('games')
        .doc(gameId)
        .collection('scores')
        .add({
          'score': points,
          'userId': userId,
          'questionId': questionId,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }
}
