import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String question;
  final String correctAnswer;
  final String explanation;
  final String type;

  Question({
    required this.question,
    required this.correctAnswer,
    required this.explanation,
    required this.type,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      question: json['question'] as String,
      correctAnswer: json['correctAnswer'] as String,
      explanation: json['explanation'] as String,
      type: json['type'] as String,
    );
  }
}

class QuestionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Question>> generateQuestions(
    String subject, {
    String? syllabus,
    String? topic,
  }) async {
    try {
      // Create a document in the questions collection
      DocumentReference docRef = await _firestore.collection('questions').add({
        'subject': subject,
        'syllabus': syllabus,
        'topic': topic,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Wait for the Cloud Function to process and update the document
      DocumentSnapshot snapshot = await docRef.get();
      while (snapshot.get('status') == 'pending') {
        await Future.delayed(const Duration(seconds: 1));
        snapshot = await docRef.get();
      }

      if (snapshot.get('status') == 'error') {
        throw Exception(snapshot.get('error'));
      }

      final questionsJson = jsonDecode(snapshot.get('questions') as String);
      return (questionsJson['questions'] as List)
          .map((q) => Question.fromJson(q as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to generate questions: $e');
    }
  }
}
