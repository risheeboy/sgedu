import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<void> submitFeedback({
    required String questionId,
    required String userId,
    required String type,
    List<String>? reasons,
    String? comment,
  }) async {
    await _firestore.collection('feedbacks').add({
      'questionId': questionId,
      'userId': userId,
      'type': type,
      'reasons': reasons,
      'comment': comment,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
