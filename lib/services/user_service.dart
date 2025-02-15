import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> updateLastLogin(String userId) async {
    if (userId.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }
    await _firestore.collection('users').doc(userId).set({
      'lastLogin': FieldValue.serverTimestamp(),
      'userId': userId,
    }, SetOptions(merge: true));
  }
}
