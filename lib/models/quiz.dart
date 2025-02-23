import 'package:cloud_firestore/cloud_firestore.dart';

class Quiz {
  final String id;
  final String name;
  final List<String> questionIds;
  final String userId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Quiz({
    required this.id,
    required this.name,
    required this.questionIds,
    required this.userId,
    required this.createdAt,
    this.updatedAt,
  });

  // Convert Firestore document to Quiz object
  factory Quiz.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Quiz(
      id: doc.id,
      name: data['name'] ?? '',
      questionIds: List<String>.from(data['questionIds'] ?? []),
      userId: data['userId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Convert Quiz object to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'questionIds': questionIds,
      'userId': userId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  factory Quiz.fromJson(Map<String, dynamic> json) {
    return Quiz(
      id: json['id'],
      name: json['name'],
      questionIds: List<String>.from(json['questionIds']),
      userId: json['userId'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }
}
