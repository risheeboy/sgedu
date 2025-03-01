import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game.dart';
import '../models/question.dart';
import '../services/game_service.dart';
import '../services/question_service.dart';
import '../widgets/common_app_bar.dart';
import 'package:go_router/go_router.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  
  const GameScreen({
    Key? key,
    required this.gameId,
  }) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameService _gameService = GameService();
  final QuestionService _questionService = QuestionService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Stream<Game?>? _gameStream;
  Stream<List<GameScore>>? _scoresStream;
  
  Question? _currentQuestion;
  bool _loading = true;
  String? _error;
  bool _showAnswer = false;
  String? _selectedMcqOption;
  bool _answerSubmitted = false;
  final TextEditingController _userAnswerController = TextEditingController();
  
  // Current scores map for quick lookup
  Map<String, int> _playerScores = {};
  
  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }
  
  void _initializeStreams() {
    _gameStream = _gameService.getGameStream(widget.gameId);
    _scoresStream = _gameService.getGameScoresStream(widget.gameId);
    
    // Listen to score changes to update leaderboard
    _scoresStream?.listen((scores) {
      // Reset scores
      final newScores = <String, int>{};
      
      // Calculate total score for each player
      for (var score in scores) {
        newScores[score.userId] = (newScores[score.userId] ?? 0) + score.score;
      }
      
      setState(() {
        _playerScores = newScores;
      });
    });
    
    // Listen to game changes to update current question
    _gameStream?.listen((game) {
      if (game != null && game.status == GameStatus.inProgress) {
        _loadCurrentQuestion(game);
      }
    });
  }
  
  Future<void> _loadCurrentQuestion(Game game) async {
    setState(() {
      _loading = true;
      _error = null;
      _showAnswer = false;
      _selectedMcqOption = null;
      _answerSubmitted = false;
      _userAnswerController.clear();
    });
    
    try {
      // Get the current question ID
      final currentQuestionId = await _gameService.getCurrentQuestionId(game.id);
      
      if (currentQuestionId == null) {
        setState(() {
          _error = 'No question available';
          _loading = false;
        });
        return;
      }
      
      // Check if user has already answered this question
      final userScores = await FirebaseFirestore.instance
          .collection('games')
          .doc(game.id)
          .collection('scores')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .where('questionId', isEqualTo: currentQuestionId)
          .get();
      
      // If user has already answered, mark as submitted
      final hasSubmitted = userScores.docs.isNotEmpty;
      
      // Get the question
      final question = await _questionService.getQuestionById(currentQuestionId);
      
      setState(() {
        _currentQuestion = question;
        _loading = false;
        _answerSubmitted = hasSubmitted;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading question: $e';
        _loading = false;
      });
    }
  }
  
  void _showAnswerFeedback() {
    setState(() {
      _showAnswer = true;
    });
  }
  
  Future<void> _submitAnswer() async {
    if (_currentQuestion == null || _answerSubmitted) return;
    
    String answer = '';
    bool isCorrect = false;
    
    // Get the answer based on question type
    if (_currentQuestion!.type.toLowerCase() == 'mcq') {
      if (_selectedMcqOption == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an answer')),
        );
        return;
      }
      answer = _selectedMcqOption!;
      isCorrect = answer.toLowerCase() == _currentQuestion!.correctAnswer.toLowerCase();
    } else {
      // For short answer questions
      answer = _userAnswerController.text.trim();
      if (answer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an answer')),
        );
        return;
      }
      
      // Basic comparison - could be enhanced with more sophisticated matching
      isCorrect = answer.toLowerCase() == _currentQuestion!.correctAnswer.toLowerCase();
    }
    
    try {
      await _gameService.submitAnswer(
        gameId: widget.gameId,
        questionId: _currentQuestion!.id!,
        answer: answer,
        isCorrect: isCorrect,
      );
      
      setState(() {
        _answerSubmitted = true;
        _showAnswer = true; // Show answer feedback automatically after submission
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting answer: $e')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: 'Quiz Game'),
      body: StreamBuilder<Game?>(
        stream: _gameStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }
          
          final game = snapshot.data;
          if (game == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Game not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.go('/games');
                    },
                    child: const Text('Return to Game Lobby'),
                  ),
                ],
              ),
            );
          }
          
          // Show appropriate screen based on game status
          if (game.status == GameStatus.waiting) {
            return _buildWaitingScreen(game);
          } else if (game.status == GameStatus.completed) {
            return _buildGameCompletedScreen(game);
          } else {
            return _buildGameInProgressScreen(game);
          }
        },
      ),
    );
  }
  
  Widget _buildWaitingScreen(Game game) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Waiting for the game to start...'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context.go('/game/${game.id}/lobby');
            },
            child: const Text('Go to Lobby'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGameCompletedScreen(Game game) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'Game Completed!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Final Results:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildLeaderboard(game),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  context.go('/games');
                },
                child: const Text('Return to Lobby'),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildGameInProgressScreen(Game game) {
    return Row(
      children: [
        // Game content area
        Expanded(
          flex: 3,
          child: _buildQuestionArea(game),
        ),
        // Leaderboard sidebar
        Expanded(
          flex: 1,
          child: _buildLeaderboard(game),
        ),
      ],
    );
  }
  
  Widget _buildQuestionArea(Game game) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Text(_error!),
      );
    }
    
    if (_currentQuestion == null) {
      return const Center(
        child: Text('No question available'),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question ${game.currentQuestionIndex + 1}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _currentQuestion!.question,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    
                    // Different UI based on question type
                    if (_currentQuestion!.type.toLowerCase() == 'mcq')
                      ..._buildMcqOptions()
                    else
                      _buildShortAnswerInput(),
                      
                    const SizedBox(height: 16),
                    
                    // Show submit button if not yet submitted
                    if (!_answerSubmitted)
                      ElevatedButton(
                        onPressed: _submitAnswer,
                        child: const Text('Submit Answer'),
                      ),
                      
                    // Show feedback if answer was submitted or if showing answer
                    if (_showAnswer || _answerSubmitted)
                      ..._buildAnswerFeedback(),
                  ],
                ),
              ),
            ),
            
            // Host controls
            if (game.hostId == _auth.currentUser?.uid)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Host Controls',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              await _gameService.nextQuestion(game.id);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          child: const Text('Next Question'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  List<Widget> _buildMcqOptions() {
    final options = _currentQuestion!.mcqChoices ?? [];
    
    if (options.isEmpty) {
      return [
        _buildShortAnswerInput(), // Fallback to text input if no options
      ];
    }
    
    return options.map((option) {
      final isSelected = option == _selectedMcqOption;
      final isCorrect = _showAnswer && option.toLowerCase() == _currentQuestion!.correctAnswer.toLowerCase();
      final isIncorrect = _showAnswer && isSelected && option.toLowerCase() != _currentQuestion!.correctAnswer.toLowerCase();
      
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        color: isSelected ? Colors.blue.shade100 : null,
        child: InkWell(
          onTap: _answerSubmitted ? null : () {
            setState(() {
              _selectedMcqOption = option;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      color: isCorrect
                          ? Colors.green
                          : isIncorrect
                              ? Colors.red
                              : null,
                      fontWeight: isCorrect || isSelected ? FontWeight.bold : null,
                    ),
                  ),
                ),
                if (isCorrect)
                  const Icon(Icons.check_circle, color: Colors.green)
                else if (isIncorrect)
                  const Icon(Icons.cancel, color: Colors.red),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
  
  Widget _buildShortAnswerInput() {
    return TextField(
      controller: _userAnswerController,
      decoration: const InputDecoration(
        labelText: 'Your Answer',
        border: OutlineInputBorder(),
      ),
      enabled: !_answerSubmitted,
    );
  }
  
  List<Widget> _buildAnswerFeedback() {
    String answer = '';
    bool isCorrect = false;
    
    // Determine correctness based on question type
    if (_currentQuestion!.type.toLowerCase() == 'mcq') {
      answer = _selectedMcqOption ?? '';
      isCorrect = answer.toLowerCase() == _currentQuestion!.correctAnswer.toLowerCase();
    } else {
      answer = _userAnswerController.text.trim();
      isCorrect = answer.toLowerCase() == _currentQuestion!.correctAnswer.toLowerCase();
    }
    
    return [
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 8),
      Text(
        isCorrect ? '✅ Correct!' : '❌ Incorrect',
        style: TextStyle(
          color: isCorrect ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Correct answer: ${_currentQuestion!.correctAnswer}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text('Explanation: ${_currentQuestion!.explanation}'),
    ];
  }
  
  Widget _buildLeaderboard(Game game) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(
          left: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leaderboard',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          
          // Show players and their scores
          Expanded(
            child: _playerScores.isEmpty
                ? const Center(child: Text('No scores yet'))
                : ListView(
                    children: () {
                        final sortedEntries = _playerScores.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        return sortedEntries.map((entry) {
                          final userId = entry.key;
                          final score = entry.value;
                          final playerName = game.players[userId] ?? 'Unknown';
                          final isCurrentUser = userId == _auth.currentUser?.uid;
                          
                          return Card(
                            color: isCurrentUser ? Colors.blue[50] : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      playerName,
                                      style: TextStyle(
                                        fontWeight: isCurrentUser ? FontWeight.bold : null,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$score pts',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList();
                      }(),
                  ),
          ),
          
          // Game info
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Game Status: ${game.status.toString().split('.').last}',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 4),
          Text(
            'Players: ${game.players.length}',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
