import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String? id;
  final String question;
  final String type;
  final String explanation;
  final String correctAnswer;
  final String subject;
  final String syllabus;
  final DocumentReference? request;
  final List<String>? topics;

  Question({
    required this.question,
    required this.type,
    required this.explanation,
    required this.correctAnswer,
    required this.subject,
    required this.syllabus,
    this.request,
    this.topics,
    this.id,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String?,
      question: json['question'] as String,
      type: json['type'] as String,
      explanation: json['explanation'] as String,
      correctAnswer: json['correctAnswer'] as String,
      subject: json['subject'] as String,
      syllabus: json['syllabus'] as String,
      request: json['request'] as DocumentReference?,
      topics: (json['topics'] as List<dynamic>?)?.cast<String>(),
    );
  }

  factory Question.fromMap(Map<String, dynamic> data, {String? id}) {
    return Question(
      id: id ?? data['id'] as String,
      question: data['question'] as String,
      type: data['type'] as String? ?? '',
      explanation: data['explanation'] as String,
      correctAnswer: data['correctAnswer'] as String,
      subject: data['subject'] as String,
      syllabus: data['syllabus'] as String,
      request: null,
      topics: null,
    );
  }
}
