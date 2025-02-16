import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/feedback_service.dart';
import 'chat_dialog.dart';
import '../services/quiz_service.dart'; 

class QuestionCard extends StatefulWidget {
  final dynamic question;
  final int index;

  const QuestionCard({
    super.key, 
    required this.question,
    required this.index,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  bool _showAnswer = false;
  Set<String> _selectedQuizIds = {};
  bool _updatingQuizzes = false;
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

  Future<void> _showNegativeFeedbackOptions() async {
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

  Future<void> _showQuizSelectionDialog() async {
    final quizService = QuizService();
    
    // Get current quiz selections
    _selectedQuizIds = Set.from(
      await quizService.getQuizzesContainingQuestion({
        'question': widget.question.question,
        'correctAnswer': widget.question.correctAnswer,
        'explanation': widget.question.explanation,
      })
    );
    
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StreamBuilder<QuerySnapshot>(
        stream: quizService.getUserQuizzesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final quizzes = snapshot.data!.docs;
          
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Add to Quizzes'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...quizzes.map((quiz) {
                      final data = quiz.data() as Map<String, dynamic>;
                      return CheckboxListTile(
                        title: Text(data['name'] as String),
                        value: _selectedQuizIds.contains(quiz.id),
                        onChanged: _updatingQuizzes 
                          ? null 
                          : (checked) async {
                              setState(() => _updatingQuizzes = true);
                              try {
                                await quizService.toggleQuestionInQuiz(
                                  quizId: quiz.id,
                                  question: {
                                    'question': widget.question.question,
                                    'correctAnswer': widget.question.correctAnswer,
                                    'explanation': widget.question.explanation,
                                  },
                                  add: checked!,
                                );
                                setState(() {
                                  if (checked) {
                                    _selectedQuizIds.add(quiz.id);
                                  } else {
                                    _selectedQuizIds.remove(quiz.id);
                                  }
                                });
                              } finally {
                                setState(() => _updatingQuizzes = false);
                              }
                            },
                      );
                    }),
                    if (quizzes.isEmpty)
                      const Text('No quizzes yet. Create one below.'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final controller = TextEditingController();
                    final created = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('New Quiz'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Quiz Name',
                            hintText: 'Enter quiz name',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (controller.text.isNotEmpty) {
                                await quizService.createQuiz(
                                  name: controller.text,
                                );
                                Navigator.pop(context, true);
                              }
                            },
                            child: const Text('Create'),
                          ),
                        ],
                      ),
                    );
                    if (created == true) {
                      setState(() {}); // Refresh list
                    }
                  },
                  child: const Text('New Quiz'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: widget.question.question,
              styleSheet: MarkdownStyleSheet(
                p: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 16),
              MarkdownBody(
                data: widget.question.correctAnswer,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (widget.question.explanation != null && widget.question.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Explanation:',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.orange[800],
                  ),
                ),
                const SizedBox(height: 4),
                MarkdownBody(
                  data: widget.question.explanation,
                  styleSheet: MarkdownStyleSheet(
                    p: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                // Quiz selection button
                OutlinedButton.icon(
                  onPressed: _showQuizSelectionDialog,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Quiz'),
                ),
                const SizedBox(width: 8),
                // Show/Hide answer toggle
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAnswer = !_showAnswer;
                    });
                  },
                  icon: Icon(_showAnswer ? Icons.visibility_off : Icons.visibility),
                  label: const Text('Answer'),
                ),
                const Spacer(),
                // Feedback buttons
                IconButton(
                  icon: const Icon(Icons.thumb_up, color: Colors.green),
                  iconSize: 20,
                  onPressed: () => _submitFeedback('positive'),
                ),
                IconButton(
                  icon: const Icon(Icons.thumb_down, color: Colors.red),
                  iconSize: 20,
                  onPressed: _showNegativeFeedbackOptions,
                ),
                IconButton(
                  icon: const Icon(Icons.chat),
                  tooltip: 'Ask AI Tutor',
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      final docData = {
                        'questionId': widget.question.id,
                        'context': {
                          'question': widget.question.question,
                          'answer': widget.question.correctAnswer,
                          'explanation': widget.question.explanation,
                        },
                        'userId': user.uid,
                        'messages': [],
                        'status': 'active',
                        'createdAt': FieldValue.serverTimestamp(),
                      };
                      
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
                        const SnackBar(content: Text('Please login to chat'))
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class QuizDropdown extends StatefulWidget {
  final String? selectedQuizId;
  final ValueChanged<String?> onQuizSelected;

  const QuizDropdown({super.key, this.selectedQuizId, required this.onQuizSelected});

  @override
  State<QuizDropdown> createState() => _QuizDropdownState();
}

class _QuizDropdownState extends State<QuizDropdown> {
  final TextEditingController _newQuizController = TextEditingController();

  Future<void> _createNewQuiz(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Quiz'),
        content: TextField(
          controller: _newQuizController,
          decoration: const InputDecoration(hintText: 'Enter quiz name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_newQuizController.text.isNotEmpty) {
                final newQuizId = await QuizService().createQuiz(
                  name: _newQuizController.text,
                );
                widget.onQuizSelected(newQuizId);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: QuizService().getUserQuizzesStream(),
      builder: (context, snapshot) {
        // Create default items that are always present
        final items = <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Select Quiz'),
          ),
          const DropdownMenuItem<String>(
            value: 'new',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.add),
              title: Text('New Quiz'),
            ),
          ),
        ];

        // Add quiz items if data is available
        if (snapshot.hasData) {
          items.insertAll(1, snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(data['name'] as String),
            );
          }));
        }

        // If the selected value is not in the items list, reset to empty
        final selectedValue = widget.selectedQuizId ?? '';
        final hasValue = items.any((item) => item.value == selectedValue);
        
        return DropdownButtonFormField<String>(
          value: hasValue ? selectedValue : '',
          items: items,
          onChanged: (value) {
            if (value == 'new') {
              _createNewQuiz(context);
            } else if (value != null && value.isNotEmpty) {
              widget.onQuizSelected(value);
            } else {
              widget.onQuizSelected(null);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Add to Quiz',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
        );
      },
    );
  }
}
