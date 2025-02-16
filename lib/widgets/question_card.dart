import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/feedback_service.dart';
import 'chat_dialog.dart';

class QuestionCard extends StatefulWidget {
  final dynamic question;
  final int index;

  const QuestionCard({Key? key, required this.question, required this.index}) : super(key: key);

  @override
  _QuestionCardState createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  bool _showAnswers = false;
  bool _showFeedbackOptions = false;
  Set<String> _selectedReasons = {};
  final TextEditingController _feedbackCommentController = TextEditingController();

  void _submitFeedback(String type, {List<String>? reasons, String? comment}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FeedbackService.submitFeedback(
        questionId: widget.question.id ?? '',
        userId: user.uid,
        type: type,
        reasons: reasons,
        comment: comment,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to submit feedback')
        ),
      );
    }
  }

  void _showNegativeFeedbackOptions() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('What was wrong?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('Incorrect answer'),
                  value: _selectedReasons.contains('incorrect'),
                  onChanged: (v) => setState(() {
                    v! ? _selectedReasons.add('incorrect') : _selectedReasons.remove('incorrect');
                  }),
                ),
                CheckboxListTile(
                  title: const Text('Incoherent question'),
                  value: _selectedReasons.contains('incoherent'),
                  onChanged: (v) => setState(() {
                    v! ? _selectedReasons.add('incoherent') : _selectedReasons.remove('incoherent');
                  }),
                ),
                CheckboxListTile(
                  title: const Text('Out of syllabus'),
                  value: _selectedReasons.contains('syllabus'),
                  onChanged: (v) => setState(() {
                    v! ? _selectedReasons.add('syllabus') : _selectedReasons.remove('syllabus');
                  }),
                ),
                CheckboxListTile(
                  title: const Text('Other'),
                  value: _selectedReasons.contains('other'),
                  onChanged: (v) => setState(() {
                    v! ? _selectedReasons.add('other') : _selectedReasons.remove('other');
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (_selectedReasons.contains('other')) {
                    final comment = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Additional comments'),
                        content: TextField(
                          controller: _feedbackCommentController,
                          decoration: const InputDecoration(
                            hintText: 'Please explain the issue...',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, _feedbackCommentController.text),
                            child: const Text('Submit'),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  _submitFeedback(
                    'negative',
                    reasons: _selectedReasons.toList(),
                    comment: _feedbackCommentController.text,
                  );
                  _selectedReasons.clear();
                  _feedbackCommentController.clear();
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.thumb_up, color: Colors.green),
                      iconSize: 12,
                      onPressed: () => _submitFeedback('positive'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.thumb_down, color: Colors.red),
                      iconSize: 12,
                      onPressed: _showNegativeFeedbackOptions,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat),
                      tooltip: 'Ask AI Tutor',
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          print('[DEBUG] Current User UID: ${user.uid}');
                          
                          final docData = {
                            'questionId': widget.question.id,
                            'context': {
                              'question': widget.question.question ?? '',
                              'answer': widget.question.correctAnswer ?? '',
                              'explanation': widget.question.explanation ?? '',
                            },
                            'userId': user.uid,
                            'messages': [],
                            'status': 'active',
                            'createdAt': FieldValue.serverTimestamp(),
                          };
                          
                          print('[DEBUG] Chat Session Data: $docData');
                          
                          final doc = await FirebaseFirestore.instance
                              .collection('chat_sessions')
                              .add(docData);
                          
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => ChatDialog(
                                chatSessionId: doc.id,
                              ),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Please login to chat'))
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.question.question,
              style: const TextStyle(fontSize: 16),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAnswers = !_showAnswers;
                  });
                },
                icon: Icon(_showAnswers ? Icons.visibility_off : Icons.visibility),
                label: Text(_showAnswers ? 'Hide Answer' : 'Show Answer'),
              ),
            ),
            if (_showAnswers) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Answer:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 8),
              MarkdownBody(
                data: widget.question.correctAnswer,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14.0),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Explanation:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
              const SizedBox(height: 8),
              MarkdownBody(
                data: widget.question.explanation,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14.0),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
