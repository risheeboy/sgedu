import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/question.dart';

class QuestionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Question>> generateQuestions(
    String subject, {
    String? syllabus,
    String? topic,
  }) async {
    try {

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null)
        throw Exception('User needs to log in before generating questions');

      // Create a document in the requests collection
      final data = {
        'subject': subject,
        'syllabus': syllabus,
        'topic': topic,
        'userId': currentUser.uid,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      };

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

  Future<List<Question>> getQuestions({
    required String syllabus, 
    required String subject, 
    String? topic, 
    int limit = 1, 
    int page = 1}) async {
    try {
      print("Getting questions: $syllabus, $subject, $topic, limit: $limit, page: $page");
      Query query = FirebaseFirestore.instance.collection('questions')
          .where('syllabus', isEqualTo: syllabus)
          .where('subject', isEqualTo: subject);
      
      if (topic != null) {
        query = query.where('topics', arrayContains: topic);
      }

      // Add orderBy clauses for all fields used in startAfter
      query = query.orderBy('timestamp', descending: true);

      // Calculate skip based on page number and limit
      int skip = (page - 1) * limit;

      // First get the last document of the previous page
      if (skip > 0) {
        QuerySnapshot skipDocs = await query.limit(skip).get();
        if (skipDocs.docs.isNotEmpty) {
          DocumentSnapshot lastDoc = skipDocs.docs.last;
          query = query.startAfter([lastDoc.get('timestamp')]);
        }
      }

      // Apply the limit for current page
      query = query.limit(limit);

      QuerySnapshot snapshot = await query.get();
      return snapshot.docs.map((doc) => Question.fromMap(doc.data() as Map<String, dynamic>, id: doc.id)).toList();
    } catch (e) {
      throw Exception('Error retrieving questions from Firestore: $e');
    }
  }

  Future<Question> getQuestionById(String id) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('questions').doc(id).get();
      if (doc.exists) {
        return Question.fromMap(doc.data() as Map<String, dynamic>, id: doc.id);
      }
      throw Exception('Question not found');
    } catch (e) {
      throw Exception('Error fetching question: $e');
    }
  }
}
