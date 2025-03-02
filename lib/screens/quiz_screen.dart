import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/quiz.dart';
import '../services/quiz_service.dart';
import '../services/question_service.dart';
import '../models/question.dart';
import '../widgets/common_app_bar.dart';

class QuizScreen extends StatefulWidget {
  final String quizId;
  final String? sourceQuestionId;
  
  const QuizScreen({
    Key? key,
    required this.quizId,
    this.sourceQuestionId,
  }) : super(key: key);

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final QuizService _quizService = QuizService();
  final QuestionService _questionService = QuestionService();
  Quiz? _quiz;
  List<Question>? _questions;
  bool _loading = true;
  String? _error;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    print('QuizScreen initialized with quiz ID: ${widget.quizId}');
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    try {
      // Get quiz document
      final quizDoc = await FirebaseFirestore.instance
          .collection('quizzes')
          .doc(widget.quizId)
          .get();

      if (!quizDoc.exists) {
        setState(() {
          _error = 'Quiz not found';
          _loading = false;
        });
        return;
      }

      final quiz = Quiz.fromFirestore(quizDoc);
      
      // Load all questions for this quiz
      final questionsList = await Future.wait(
        quiz.questionIds.map((id) => _questionService.getQuestionById(id))
      );

      // Filter out null values and ensure the questions are in the same order as the questionIds
      final questions = <Question>[];
      for (var id in quiz.questionIds) {
        final question = questionsList
            .whereType<Question>()
            .firstWhere((q) => q.id == id, orElse: () => null as Question);
        if (question != null) {
          questions.add(question);
        }
      }

      setState(() {
        _quiz = quiz;
        _questions = questions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading quiz: $e';
        _loading = false;
      });
    }
  }

  void _handleBackButton() {
    if (widget.sourceQuestionId != null && widget.sourceQuestionId!.isNotEmpty) {
      print('Navigating back to source question: ${widget.sourceQuestionId}');
      context.go('/question/${widget.sourceQuestionId}');
    } else {
      context.go('/');
    }
  }

  Future<void> _saveQuestionOrder() async {
    if (_quiz == null || _questions == null) return;
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Extract the question IDs in the current order
      final newQuestionIds = _questions!.map((q) => q.id!).toList();
      
      // Save the new order
      await _quizService.updateQuestionOrder(
        quizId: widget.quizId,
        newQuestionIds: newQuestionIds,
      );
      
      // Exit editing mode
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question order saved')),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving question order: $e')),
      );
    }
  }

  Future<void> _removeQuestion(String questionId) async {
    if (_quiz == null) return;
    
    setState(() {
      _isRemoving = true;
    });
    
    try {
      await _quizService.removeQuestionFromQuiz(
        quizId: widget.quizId,
        questionId: questionId,
      );
      
      // Reload quiz to update the UI
      await _loadQuiz();
      
      setState(() {
        _isRemoving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question removed from quiz')),
      );
    } catch (e) {
      setState(() {
        _isRemoving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing question: $e')),
      );
    }
  }

  void _confirmRemoveQuestion(Question question) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Question?'),
        content: Text('Are you sure you want to remove this question from the quiz?\n\n"${question.question}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeQuestion(question.id!);
            },
            child: const Text('Remove'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final Question item = _questions!.removeAt(oldIndex);
      _questions!.insert(newIndex, item);
    });
  }

  void _toggleEditMode() {
    if (_isEditing) {
      // Prompt to save changes
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Changes?'),
          content: const Text('Do you want to save the new question order?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isEditing = false;
                });
                _loadQuiz(); // Reload original order
              },
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveQuestionOrder();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else {
      setState(() {
        _isEditing = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: CommonAppBar(
          title: 'Quiz Error',
          showQuizButton: true,
        ),
        body: Center(
          child: Text(_error!),
        ),
      );
    }

    if (_quiz == null || _questions == null || _questions!.isEmpty) {
      return Scaffold(
        appBar: CommonAppBar(
          title: 'Quiz',
          showQuizButton: true,
        ),
        body: const Center(
          child: Text('No questions available'),
        ),
      );
    }

    // Check if the current user is the owner of the quiz
    final isOwner = _quiz!.userId == FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: CommonAppBar(
        title: _quiz!.name,
        shareUrl: '${Uri.base.origin}/quiz/${widget.quizId}',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBackButton,
        ),
        automaticallyImplyLeading: false,
        additionalActions: [
          if (isOwner && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Question Order',
              onPressed: _toggleEditMode,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing
                  ? 'Drag and drop questions to reorder them:'
                  : 'Questions in this quiz:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isRemoving
                  ? const Center(child: CircularProgressIndicator())
                  : _isEditing
                      ? ReorderableListView.builder(
                          itemCount: _questions!.length,
                          onReorder: _onReorder,
                          itemBuilder: (context, index) {
                            final question = _questions![index];
                            return Card(
                              key: ValueKey(question.id),
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              child: ListTile(
                                leading: const Icon(Icons.drag_handle),
                                title: Text(
                                  'Question ${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  question.question,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  tooltip: 'Remove Question',
                                  onPressed: () => _confirmRemoveQuestion(question),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          itemCount: _questions!.length,
                          itemBuilder: (context, index) {
                            final question = _questions![index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  question.question,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${question.type} - ${question.subject}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                trailing: isOwner
                                    ? IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        tooltip: 'Remove Question',
                                        onPressed: () => _confirmRemoveQuestion(question),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: _isEditing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _saveQuestionOrder,
                            icon: const Icon(Icons.save),
                            label: const Text('Save Question Order'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isEditing = false;
                              });
                              _loadQuiz(); // Reload original order
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel Editing'),
                          ),
                        ],
                      )
                    : ElevatedButton.icon(
                        onPressed: _toggleEditMode,
                        icon: const Icon(Icons.reorder),
                        label: const Text('Reorder Questions'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
