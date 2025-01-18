import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> generateQuestions(String subject, String level) async {
    try {
      // Create a document in the questions collection
      DocumentReference docRef = await _firestore.collection('questions').add({
        'subject': subject,
        'level': level,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Wait for the Cloud Function to process and update the document
      DocumentSnapshot snapshot = await docRef.get();
      while (snapshot.get('status') == 'pending') {
        await Future.delayed(const Duration(seconds: 1));
        snapshot = await docRef.get();
      }

      return snapshot.get('questions') as String;
    } catch (e) {
      throw Exception('Failed to generate questions: $e');
    }
  }
}
