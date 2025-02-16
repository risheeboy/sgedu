import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuizService {
  final CollectionReference _quizzes = FirebaseFirestore.instance.collection('quizzes');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot> getUserQuizzesStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.empty();
    }
    
    return _quizzes
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<String> createQuiz({required String name}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to create a quiz');
    }

    final docRef = await _quizzes.add({
      'name': name,
      'userId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'questionIds': [],
    });
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

    final quizData = quizDoc.data() as Map<String, dynamic>;
    if (quizData['userId'] != user.uid) {
      throw Exception('Not authorized to modify this quiz');
    }

    final questionIds = List<String>.from(quizData['questionIds'] ?? []);
    
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
          final data = doc.data() as Map<String, dynamic>;
          final questionIds = List<String>.from(data['questionIds'] ?? []);
          return questionIds.contains(questionId);
        })
        .map((doc) => doc.id)
        .toList();
  }
}
