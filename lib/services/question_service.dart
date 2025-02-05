import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String question;
  final String type;
  final String explanation;
  final String correctAnswer;

  Question({
    required this.question,
    required this.type,
    required this.explanation,
    required this.correctAnswer,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      question: json['question'] as String,
      type: json['type'] as String,
      explanation: json['explanation'] as String,
      correctAnswer: json['correctAnswer'] as String,
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

      try {
        final questionsJson = jsonDecode(snapshot.get('questions') as String);
        return (questionsJson['questions'] as List)
            .map((q) => Question.fromJson(q as Map<String, dynamic>))
            .toList();
      } catch (e) {
        print('Raw questions JSON: ${snapshot.get('questions')}');
        print('JSON Decode Error: $e');
        throw Exception('Failed to parse questions: $e');
      }
    } catch (e) {
      throw Exception('Failed to generate questions: $e');
    }
  }
}
