import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Question {
  final String question;
  final String type;
  final String explanation;
  final String correctAnswer;
  final String subject;
  final String syllabus;
  final DocumentReference request;
  final List<String>? topics;

  Question({
    required this.question,
    required this.type,
    required this.explanation,
    required this.correctAnswer,
    required this.subject,
    required this.syllabus,
    required this.request,
    this.topics,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      question: json['question'] as String,
      type: json['type'] as String,
      explanation: json['explanation'] as String,
      correctAnswer: json['correctAnswer'] as String,
      subject: json['subject'] as String,
      syllabus: json['syllabus'] as String,
      request: json['request'] as DocumentReference,
      topics: (json['topics'] as List<dynamic>).cast<String>(),
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
      // Create a document in the requests collection
      final data = {
        'subject': subject,
        'syllabus': syllabus,
        'topic': topic,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      };

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        data['userId'] = currentUser.uid;
      }

      DocumentReference docRef = await _firestore.collection('requests').add(data);

      // Wait for the Cloud Function to process and update the document
      DocumentSnapshot snapshot = await docRef.get();
      while (snapshot.get('status') == 'pending') { // TODO : Add timeout
        await Future.delayed(const Duration(seconds: 1));
        snapshot = await docRef.get();
      }

      if (snapshot.get('status') == 'error') {
        throw Exception(snapshot.get('error'));
      }

      try {
        // New query from collection questions, with reference to the request document
        QuerySnapshot snapshot = await _firestore
            .collection('questions')
            .where('request', isEqualTo: docRef)
            .get();

        List<Question> questions = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Question.fromJson(data);
        }).toList();

        // Return the list of questions
        return questions;
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
