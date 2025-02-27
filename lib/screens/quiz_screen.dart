import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
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
  int _currentQuestionIndex = 0;
  bool _loading = true;
  String? _error;
  bool _showAnswer = false;
  String? _selectedMcqOption;
  final TextEditingController _userAnswerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('QuizScreen initialized with quiz ID: ${widget.quizId}');
    _loadQuiz();
    _updateBrowserUrl();
  }

  void _updateBrowserUrl() {
    final quizPath = '/quiz/${widget.quizId}';
    final currentPath = html.window.location.pathname;
    
    // Check if we need to update the URL
    if (currentPath == null || !currentPath.endsWith(quizPath)) {
      print('Updating browser URL to: $quizPath');
      // Use replaceState instead of pushState to avoid adding to history stack
      html.window.history.replaceState(null, '', quizPath);
    } else {
      print('Browser URL already correct: $currentPath');
    }
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
      final questions = await Future.wait(
        quiz.questionIds.map((id) => _questionService.getQuestionById(id))
      );

      setState(() {
        _quiz = quiz;
        _questions = questions.whereType<Question>().toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading quiz: $e';
        _loading = false;
      });
    }
  }

  void _nextQuestion() {
    if (_questions != null && _currentQuestionIndex < _questions!.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _showAnswer = false;
        _selectedMcqOption = null;
        _userAnswerController.clear();
      });
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
        _showAnswer = false;
        _selectedMcqOption = null;
        _userAnswerController.clear();
      });
    }
  }

  void _selectMcqOption(String option) {
    setState(() {
      _selectedMcqOption = option;
      _showAnswer = true;
    });
  }

  void _handleBackButton() {
    String targetPath = '/';
    
    // First check if we have a source question ID from the widget
    if (widget.sourceQuestionId != null && widget.sourceQuestionId!.isNotEmpty) {
      print('Navigating back to source question: ${widget.sourceQuestionId}');
      targetPath = '/question/${widget.sourceQuestionId}';
    } else {
      // Otherwise check document.referrer to see where we came from
      try {
        final referrer = html.document.referrer;
        if (referrer.isNotEmpty) {
          final referrerUri = Uri.parse(referrer);
          // Check if referrer is from the same origin (to avoid security issues)
          if (referrerUri.origin == Uri.base.origin) {
            final path = referrerUri.path;
            if (path.contains('/question/')) {
              targetPath = path;
              print('Navigating back to referrer path: $targetPath');
            }
          }
        }
      } catch (e) {
        print('Error handling back navigation: $e');
      }
    }
    
    // Update browser URL before navigation
    print('Setting URL to: $targetPath before navigation');
    html.window.history.replaceState(null, '', targetPath);
    
    // Navigate back
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _userAnswerController.dispose();
    super.dispose();
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

    final currentQuestion = _questions![_currentQuestionIndex];
    final hasMcqChoices = currentQuestion.mcqChoices != null && 
                          currentQuestion.mcqChoices!.isNotEmpty;

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
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Question ${_currentQuestionIndex + 1}/${_questions!.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    currentQuestion.question,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Display MCQ options if available
              if (hasMcqChoices) ...[
                ...currentQuestion.mcqChoices!.map((choice) => 
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    color: _selectedMcqOption == choice 
                        ? Colors.blue.shade100 
                        : null,
                    child: InkWell(
                      onTap: _showAnswer ? null : () => _selectMcqOption(choice),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                choice,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            if (_showAnswer && choice == currentQuestion.correctAnswer)
                              const Icon(Icons.check_circle, color: Colors.green)
                            else if (_showAnswer && _selectedMcqOption == choice && choice != currentQuestion.correctAnswer)
                              const Icon(Icons.cancel, color: Colors.red),
                          ],
                        ),
                      ),
                    ),
                  )
                ).toList(),
                const SizedBox(height: 16),
              ],
              
              // For non-MCQ questions, show text area for user to write their answer if answer not shown yet
              if (!hasMcqChoices && !_showAnswer) ...[
                const SizedBox(height: 16),
                Text(
                  'Your Answer:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _userAnswerController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(12),
                      hintText: 'Type your answer here...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _showAnswer = true),
                  child: const Text('Show Answer'),
                ),
              ],
              
              // Only show answer if it's an MCQ with a selection made or if the show answer button was clicked
              if ((hasMcqChoices && _selectedMcqOption != null) || _showAnswer) ...[
                // For non-MCQ questions, show the user's answer in read-only mode
                if (!hasMcqChoices && _userAnswerController.text.isNotEmpty) ...[
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
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentQuestion.correctAnswer,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (currentQuestion.explanation.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Explanation:',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentQuestion.explanation,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 50), // Add some bottom padding
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: _currentQuestionIndex > 0 ? _previousQuestion : null,
                    child: const Text('Previous'),
                  ),
                  ElevatedButton(
                    onPressed: _currentQuestionIndex < _questions!.length - 1 
                      ? _nextQuestion 
                      : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
