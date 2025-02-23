import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/quiz.dart';

class QuizService {
  final CollectionReference _quizzes = FirebaseFirestore.instance.collection('quizzes');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<Quiz>> getUserQuizzesStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }
    
    return _quizzes
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Quiz.fromFirestore(doc))
            .toList());
  }

  Future<String> createQuiz({required String name}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to create a quiz');
    }

    // Create a new document reference to get the ID
    final docRef = _quizzes.doc();
    
    final quiz = Quiz(
      id: docRef.id,
      name: name,
      userId: user.uid,
      questionIds: [],
      createdAt: DateTime.now(),
    );

    await docRef.set(quiz.toFirestore());
    return docRef.id;
  }

  Future<void> toggleQuestionInQuiz({
    required String quizId,
    required String questionId,
    required bool add,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to modify quiz');
    }

    final quizDoc = await _quizzes.doc(quizId).get();
    if (!quizDoc.exists) {
      throw Exception('Quiz not found');
    }

    final quiz = Quiz.fromFirestore(quizDoc);
    if (quiz.userId != user.uid) {
      throw Exception('Not authorized to modify this quiz');
    }

    final questionIds = List<String>.from(quiz.questionIds);
    
    if (add) {
      if (!questionIds.contains(questionId)) {
        questionIds.add(questionId);
      }
    } else {
      questionIds.remove(questionId);
    }

    await _quizzes.doc(quizId).update({
      'questionIds': questionIds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>> getQuizzesContainingQuestion(String questionId) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final querySnapshot = await _quizzes
        .where('userId', isEqualTo: user.uid)
        .get();

    return querySnapshot.docs
        .where((doc) {
          final quiz = Quiz.fromFirestore(doc);
          return quiz.questionIds.contains(questionId);
        })
        .map((doc) => doc.id)
        .toList();
  }
}
