import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/quiz.dart';
import '../services/quiz_service.dart';
import '../services/feedback_service.dart';
import 'chat_dialog.dart';
import 'styled_card.dart';

class QuestionCard extends StatefulWidget {
  final dynamic question;
  final int index;
  final TextEditingController topicController;

  const QuestionCard({
    super.key, 
    required this.question,
    required this.index,
    required this.topicController,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  bool _showAnswer = false;
  Set<String> _selectedQuizIds = {};
  bool _updatingQuizzes = false;
  Set<String> _selectedReasons = {};
  final TextEditingController _feedbackCommentController = TextEditingController();
  final TextEditingController _userAnswerController = TextEditingController();
  String? _selectedMcqOption;

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
      await quizService.getQuizzesContainingQuestion(widget.question.id)
    );
    
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StreamBuilder<List<Quiz>>(
        stream: quizService.getUserQuizzesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final quizzes = snapshot.data!;
          
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Add to Quizzes'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...quizzes.map((quiz) => CheckboxListTile(
                      title: Text(quiz.name),
                      value: _selectedQuizIds.contains(quiz.id),
                      onChanged: _updatingQuizzes 
                        ? null 
                        : (checked) async {
                            setState(() => _updatingQuizzes = true);
                            try {
                              await quizService.toggleQuestionInQuiz(
                                quizId: quiz.id,
                                questionId: widget.question.id,
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
                    )),
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
                            onPressed: () => Navigator.pop(context),
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

  Future<void> _showFeedbackDialog() async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Feedback'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Useful'),
                  trailing: IconButton(
                    iconSize: 15,
                    icon: const Icon(Icons.thumb_up),
                    onPressed: () => _submitFeedback('positive'),
                  ),
                ),
                ListTile(
                  title: const Text('Not Useful'),
                  trailing: IconButton(
                    iconSize: 15,
                    icon: const Icon(Icons.thumb_down),
                    onPressed: _showNegativeFeedbackOptions,
                  ),
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
    final hasMcqChoices = widget.question.mcqChoices != null && 
                          widget.question.mcqChoices!.isNotEmpty;

    return StyledCard(
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
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Wrap(
                spacing: 8.0,
                children: (widget.question.topics ?? []).map<Widget>((topic) => ActionChip(
                  label: Text(topic),
                  onPressed: () async {
                    widget.topicController.text = topic;
                  },
                )).toList(),
              ),
            ),
            
            // Display MCQ choices if available
            if (hasMcqChoices) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.question.mcqChoices!.map<Widget>((choice) => 
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    color: _selectedMcqOption == choice 
                        ? Colors.blue.shade100 
                        : null,
                    child: InkWell(
                      onTap: _showAnswer ? null : () {
                        setState(() {
                          _selectedMcqOption = choice;
                          _showAnswer = true;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                choice,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            if (_showAnswer && choice == widget.question.correctAnswer)
                              const Icon(Icons.check_circle, color: Colors.green)
                            else if (_showAnswer && _selectedMcqOption == choice && choice != widget.question.correctAnswer)
                              const Icon(Icons.cancel, color: Colors.red),
                          ],
                        ),
                      ),
                    ),
                  )
                ).toList(),
              ),
            ],
            
            // For non-MCQ questions, show text area for user to write their answer if answer not shown yet
            if (!hasMcqChoices && !_showAnswer) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _userAnswerController,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(12),
                    hintText: 'Type your answer here...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            Row(
              children: [
                // Feedback UI - Less prominent
                InkWell(
                  onTap: () => _showFeedbackDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.rate_review, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('Feedback', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Tutor button
                Tooltip(
                  message: 'Ask AI Tutor',
                  child: TextButton.icon(
                    icon: const Icon(Icons.chat),
                    label: const Text('Tutor'),
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
                ),
                const Spacer(),
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
              ],
            ),
            
            // Only show user's answer if it's a non-MCQ question and they've entered something
            if (_showAnswer && !hasMcqChoices && _userAnswerController.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Answer:',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _userAnswerController.text,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            if (_showAnswer) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Answer:',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      const SizedBox(height: 4),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
                  ),
                ),
              ),
            ],
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
    return StreamBuilder<List<Quiz>>(
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
          items.insertAll(1, snapshot.data!.map((quiz) => DropdownMenuItem<String>(
            value: quiz.id,
            child: Text(quiz.name),
          )));
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
