import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/game.dart';
import '../models/question.dart';
import '../models/score.dart';
import '../services/game_service.dart';
import '../services/score_service.dart';
import '../widgets/common_app_bar.dart';

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
  final ScoreService _scoreService = ScoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Stream<Game?>? _gameStream;
  StreamSubscription<Game?>? _gameSubscription;
  
  Question? _currentQuestion;
  bool _loading = true;
  String? _error;
  bool _showAnswer = false;
  String? _selectedMcqOption;
  bool _answerSubmitted = false;
  final TextEditingController _userAnswerController = TextEditingController();
  bool _isSubmitting = false;
  String _feedback = '';
  bool _hasSubmittedAnswer = false;
  bool _isAnswerCorrect = false;
  
  // Current scores map for quick lookup
  Map<String, int> _playerScores = {};
  
  // Keep track of active subscriptions so we can cancel them
  StreamSubscription<Score>? _activeScoreSubscription;
  
  @override
  void initState() {
    super.initState();
    _loadGame();
    _autoJoinGame();
    _setupScoreListeners();
  }
  
  void _loadGame() {
    // Load the game
    _gameStream = _gameService.getGameStream(widget.gameId);
    
    // Listen for game updates
    _gameSubscription = _gameStream?.listen((game) {
      if (game != null && game.status == GameStatus.inProgress) {
        _loadCurrentQuestion(game);
      }
    });
  }
  
  Future<void> _loadCurrentQuestion(Game game) async {
    if (game.status != GameStatus.inProgress || game.currentQuestionIndex < 0) {
      setState(() {
        _loading = false;
        _error = 'No active question';
      });
      return;
    }

    // Reset question state when loading a new question
    _resetQuestionState();
    
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      
      final questionId = await _gameService.getCurrentQuestionId(game.id!);
      
      if (questionId == null) {
        setState(() {
          _loading = false;
          _error = 'Error: No current question ID';
        });
        return;
      }
      
      final question = await _gameService.getQuestion(questionId);
      
      if (mounted) {
        setState(() {
          _currentQuestion = question;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error loading question: ${e.toString()}';
        });
      }
    }
  }
  
  void _showAnswerFeedback() {
    setState(() {
      _showAnswer = true;
    });
  }
  
  Future<void> _submitAnswer() async {
    print('Inside _submitAnswer');
    // Don't submit if there's no current question or the answer is empty
    if (_currentQuestion == null) {
      print('No current question');
      return;
    }
    
    if (!_isAnswerReady()) {
      print('Answer not ready');
      return;
    }
    
    // Prevent duplicate submissions
    if (_isSubmitting) {
      print('Already submitting');
      return;
    }
    
    setState(() {
      _isSubmitting = true;
    });
    
    final user = _auth.currentUser;
    if (user == null) {
      print('Error: User is null');
      setState(() {
        _isSubmitting = false;
      });
      return;
    }
    
    print('Preparing to submit answer');
    
    // Get the right answer based on question type
    final String userAnswer;
    if (_currentQuestion!.mcqChoices != null && _currentQuestion!.mcqChoices!.isNotEmpty) {
      userAnswer = _selectedMcqOption ?? '';
    } else {
      userAnswer = _userAnswerController.text.trim();
    }
    
    final question = _currentQuestion!;
    
    try {
      // Handle MCQ and text questions differently
      if (question.mcqChoices != null && question.mcqChoices!.isNotEmpty) {
        // For MCQ questions, evaluate locally
        print('Processing MCQ answer locally');
        
        final isCorrect = userAnswer.toLowerCase() == question.correctAnswer.toLowerCase();
        
        // Store the result in game state
        setState(() {
          _isAnswerCorrect = isCorrect;
          _hasSubmittedAnswer = true;
          _isSubmitting = false;
          _feedback = isCorrect 
              ? 'Correct! Well done.' 
              : 'Incorrect. The correct answer is: ${question.correctAnswer}';
        });
        
        // Try to record the score to Firestore, but don't block UI on it
        try {
          // Create score document for record-keeping
          await _scoreService.submitAnswer(
            gameId: widget.gameId,
            question: question,
            userAnswer: userAnswer,
            selectedOption: _selectedMcqOption,
            isCorrect: isCorrect,
            score: isCorrect ? 1 : 0  // Award 1 point for correct answers, 0 for incorrect
          );

        } catch (scoreError) {
          // Just log the error but don't affect the UI flow
          print('Error recording score to Firestore (non-critical): $scoreError');
        }
      } else {
        // For text questions, submit for AI validation
        print('Submitting text answer for AI evaluation: $userAnswer for question ID: ${question.id}');
        
        // We need to safely handle the case where the user navigates away before
        // the score processing is complete
        DocumentReference? scoreRef;
        try {
          scoreRef = await _scoreService.submitAnswer(
            gameId: widget.gameId,
            question: question,
            userAnswer: userAnswer,
            selectedOption: null
            // No score provided, the score will be determined by the AI evaluation
          );
          
          print('Answer submitted with document ID: ${scoreRef.id}');
        } catch (submitError) {
          print('Error submitting answer: $submitError');
          if (mounted) {
            setState(() {
              _isSubmitting = false;
              _feedback = 'Error submitting answer: $submitError';
            });
          }
          return;
        }
        
        // If we get here, the score document was created successfully
        
        // Set a timeout to prevent UI from hanging indefinitely
        final timeoutTimer = Timer(const Duration(seconds: 60), () {
          print('Timeout reached while waiting for score evaluation');
          
          // Check if widget is still mounted before updating state 
          if (mounted) {
            setState(() {
              _isSubmitting = false;
              _feedback = 'Evaluation is taking longer than expected. Please check back later.';
            });
          }
          
          // Cancel any active subscription
          _activeScoreSubscription?.cancel();
          _activeScoreSubscription = null;
        });
        
        // Listen for updates to the score
        _activeScoreSubscription?.cancel();  // Cancel any existing subscription
        _activeScoreSubscription = _scoreService.getScoreStream(widget.gameId, scoreRef.id).listen((score) {
          // Cancel the timeout timer since we got a response
          timeoutTimer.cancel();
          
          print('Received score update - Status: ${score.status}');
          
          // Only process if still mounted to avoid setState after dispose
          if (!mounted) {
            print('Widget not mounted, skipping state update');
            return;
          }
          
          // If score is complete, update the UI
          if (score.status == ScoreStatus.completed) {
            setState(() {
              _isSubmitting = false;
              _hasSubmittedAnswer = true;
              _isAnswerCorrect = score.isCorrect ?? false;
              _feedback = score.feedback ?? 'No feedback available';
            });
            
            // Cancel subscription since we've got our result
            _activeScoreSubscription?.cancel();
            _activeScoreSubscription = null;
          } 
          // If there was an error, show error message
          else if (score.status == ScoreStatus.error) {
            setState(() {
              _isSubmitting = false;
              _feedback = 'Error evaluating answer: ${score.feedback ?? "Unknown error"}';
            });
            
            // Cancel subscription since we've got our result
            _activeScoreSubscription?.cancel();
            _activeScoreSubscription = null;
          }
          // Otherwise (status is still pending), just wait
        });
      }
    } catch (e) {
      print('Error in _submitAnswer: $e');
      
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _feedback = 'Error: $e';
        });
      }
    }
  }
  
  /// Automatically join the game if the user is not already a participant
  Future<void> _autoJoinGame() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      // Check if the game exists and if the user is already a participant
      final gameDoc = await FirebaseFirestore.instance
          .collection('games')
          .doc(widget.gameId)
          .get();
      
      if (!gameDoc.exists) {
        setState(() {
          _error = 'Game not found';
        });
        return;
      }
      
      final game = Game.fromFirestore(gameDoc);
      
      // Only auto-join if the game is in waiting status and the user is not already in it
      if (game.status == GameStatus.waiting && !game.players.containsKey(user.uid)) {
        await _gameService.joinGame(widget.gameId);
        // Refresh streams
        setState(() {
          _gameStream = _gameService.getGameStream(widget.gameId);
          _gameSubscription = _gameStream?.listen((game) {
            if (game != null && game.status == GameStatus.inProgress) {
              _loadCurrentQuestion(game);
            }
          });
        });
      }
    } catch (e) {
      print('Error auto-joining game: $e');
      // Don't show error to user as this is an automatic action
    }
  }
  
  // Reset the current question state
  void _resetQuestionState() {
    setState(() {
      _userAnswerController.clear();
      _selectedMcqOption = null;
      _hasSubmittedAnswer = false;
      _showAnswer = false;
      _answerSubmitted = false;
      _isSubmitting = false;
      _feedback = '';
      _isAnswerCorrect = false;
      
      // Cancel any active subscriptions to avoid conflicts
      _activeScoreSubscription?.cancel();
      _activeScoreSubscription = null;
    });
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
          child: FutureBuilder<Map<String, int>>(
            key: ValueKey('game-${game.id}-leaderboard'),
            future: _gameService.getGameLeaderboard(game.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                print('Error loading leaderboard: ${snapshot.error}');
                return Center(child: Text('Error loading scores: ${snapshot.error}'));
              }
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                print('No scores found for game ${game.id}');
                return const Center(child: Text('No scores available'));
              }
              
              final scores = snapshot.data!;
              print('Loaded final scores: $scores (one-time load)');
              
              return _buildLeaderboardWithScores(game, scores);
            },
          ),
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
  
  Widget _buildLeaderboardWithScores(Game game, Map<String, int> scores) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        border: Border(
          left: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
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
          
          Expanded(
            child: scores.isEmpty
                ? const Center(child: Text('No scores yet'))
                : ListView(
                    children: () {
                        final sortedEntries = scores.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        return sortedEntries.map((entry) {
                          final userId = entry.key;
                          final score = entry.value;
                          final playerName = game.players[userId] ?? 'Unknown';
                          final isCurrentUser = userId == _auth.currentUser?.uid;
                          
                          return Card(
                            color: isCurrentUser 
                                ? (isDarkMode ? Colors.blue[900] : Colors.blue[50])
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      playerName,
                                      style: TextStyle(
                                        fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Colors.blue[800] : Colors.blue[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      score.toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : Colors.blue[800],
                                      ),
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
        ],
      ),
    );
  }
  
  Widget _buildGameInProgressScreen(Game game) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600; // Threshold for mobile screens
    
    if (isSmallScreen) {
      return Column(
        children: [
          Expanded(
            flex: 4,
            child: _buildQuestionArea(game),
          ),
          
          ExpansionTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Leaderboard'),
                if (_playerScores.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: () {
                      final sortedEntries = _playerScores.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      return sortedEntries.take(3).map((entry) {
                        final userId = entry.key;
                        final score = entry.value;
                        final isCurrentUser = userId == _auth.currentUser?.uid;
                        
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: isCurrentUser ? Colors.blue[100] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${score}',
                              style: TextStyle(
                                fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }).toList();
                    }(),
                  ),
              ],
            ),
            children: [
              SizedBox(
                height: 150, 
                child: _buildLeaderboard(game),
              ),
            ],
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: _buildQuestionArea(game),
          ),
          Expanded(
            flex: 1,
            child: _buildLeaderboard(game),
          ),
        ],
      );
    }
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
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Question ${game.currentQuestionIndex + 1}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentQuestion!.question,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                if (_currentQuestion!.imageUrl != null && _currentQuestion!.imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Image.network(
                        _currentQuestion!.imageUrl!,
                        height: 200,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / 
                                      (loadingProgress.expectedTotalBytes ?? 1)
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Text('Error loading image');
                        },
                      ),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                ..._buildAnswerInput(),
                
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_hasSubmittedAnswer)
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : () {
                          print('Submitting answer: ${_isAnswerReady() ? 'Ready' : 'Not Ready'}');
                          if (_isAnswerReady()) {
                            _submitAnswer();
                          }
                        },
                        child: _isSubmitting 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Evaluating answer...'),
                                ],
                              )
                            : const Text('Submit Answer'),
                      ),
                  ],
                ),
                
                if (_isSubmitting)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      children: const [
                        Text(
                          'Please wait while AI is evaluating your answer...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  
                if (_showAnswer || _hasSubmittedAnswer)
                  ..._buildAnswerFeedback(game),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  List<Widget> _buildMcqOptions() {
    final options = _currentQuestion!.mcqChoices ?? [];
    
    if (options.isEmpty) {
      return [
        _buildShortAnswerInput(), 
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
  
  List<Widget> _buildAnswerFeedback(Game game) {
    if (_currentQuestion == null || _feedback.isEmpty) {
      return [];
    }

    return [
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 8),
      Text(
        _isAnswerCorrect ? '✓ Correct' : '✗ Incorrect',
        style: TextStyle(
          color: _isAnswerCorrect ? Colors.green : Colors.red,
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
      Text('Explanation:'),
      Markdown(
        data: _currentQuestion!.explanation,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      const SizedBox(height: 8),
      Text('Feedback:'),
      Markdown(
        data: _feedback,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      const SizedBox(height: 16),
      if (_auth.currentUser != null && game.hostId == _auth.currentUser!.uid)
        Center(
          child: ElevatedButton(
            onPressed: _goToNextQuestion,
            child: const Text('Next Question'),
          ),
        ),
    ];
  }
  
  List<Widget> _buildAnswerInput() {
    if (_currentQuestion == null) {
      return [];
    }
    
    if (_currentQuestion!.mcqChoices != null && _currentQuestion!.mcqChoices!.isNotEmpty) {
      return _buildMcqOptions();
    } 
    else {
      return [_buildShortAnswerInput()];
    }
  }
  
  bool _isAnswerReady() {
    if (_currentQuestion == null) return false;
    
    if (_currentQuestion!.mcqChoices != null && _currentQuestion!.mcqChoices!.isNotEmpty) {
      return _selectedMcqOption != null;
    } 
    else {
      return _userAnswerController.text.trim().isNotEmpty;
    }
  }
  
  Widget _buildLeaderboard(Game game) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        border: Border(
          left: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
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
                            color: isCurrentUser 
                                ? (isDarkMode ? Colors.blue[900] : Colors.blue[50])
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      playerName,
                                      style: TextStyle(
                                        fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Colors.blue[800] : Colors.blue[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      score.toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : Colors.blue[800],
                                      ),
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
        ],
      ),
    );
  }
  
  Future<void> _goToNextQuestion() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final gameDoc = await FirebaseFirestore.instance
        .collection('games')
        .doc(widget.gameId)
        .get();
    
    if (!gameDoc.exists) return;
    
    final game = Game.fromFirestore(gameDoc);
    
    try {
      if (game.hostId == user.uid) {
        await _gameService.nextQuestion(widget.gameId);
      } else {
        setState(() {
          _resetQuestionState();
        });
      }
    } catch (e) {
      print('Error going to next question: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
  
  void _setupScoreListeners() {
    FirebaseFirestore.instance
        .collection('games')
        .doc(widget.gameId)
        .collection('scores')
        .snapshots()
        .listen((snapshot) {
      final scores = <String, int>{};
      
      for (final doc in snapshot.docs) {
        final userId = doc.get('userId') as String;
        final score = doc.get('score') as int? ?? 0;
        print('User: $userId, Question: ${doc.get('questionId')}, Score: $score');
        
        scores[userId] = (scores[userId] ?? 0) + score;
      }
      
      if (mounted) {
        setState(() {
          _playerScores = scores;
        });
      }
    }, onError: (error) {
      print('Error listening to scores: $error');
    });
  }
  
  @override
  void dispose() {
    _userAnswerController.dispose();
    _gameSubscription?.cancel();
    _activeScoreSubscription?.cancel();
    super.dispose();
  }
}
