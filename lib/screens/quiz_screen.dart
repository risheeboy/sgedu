import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quiz.dart';
import '../services/quiz_service.dart';
import '../services/question_service.dart';
import '../models/question.dart';

class QuizScreen extends StatefulWidget {
  final String quizId;
  
  const QuizScreen({
    Key? key,
    required this.quizId,
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

  @override
  void initState() {
    super.initState();
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
      });
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
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
        appBar: AppBar(
          title: const Text('Quiz Error'),
        ),
        body: Center(
          child: Text(_error!),
        ),
      );
    }

    if (_quiz == null || _questions == null || _questions!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quiz'),
        ),
        body: const Center(
          child: Text('No questions available'),
        ),
      );
    }

    final currentQuestion = _questions![_currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(_quiz!.name),
        actions: [
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  currentQuestion.correctAnswer,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
            const Spacer(),
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
    );
  }
}
