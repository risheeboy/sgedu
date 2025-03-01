import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game.dart';
import '../models/quiz.dart';
import '../models/question.dart';
import '../services/game_service.dart';
import '../services/quiz_service.dart';
import '../services/question_service.dart';
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
  
  bool _hasTimedOut = false; // New flag for tracking timeout
  Timer? _loadingTimer; // Timer for loading timeout
  
  Game? _receivedGame; // Local variable to track if we've received game data
  
  @override
  void initState() {
    super.initState();
    print('GameScreen initState - gameId: ${widget.gameId}');
    _initializeStreams();
    _updateBrowserUrl();
    
    // Set a timeout for loading
    _loadingTimer = Timer(const Duration(seconds: 10), () {
      print('Game loading timed out after 10 seconds');
      setState(() {
        _hasTimedOut = true;
      });
    });
  }
  
  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }
  
  void _updateBrowserUrl() {
    final gamePath = '/game/${widget.gameId}';
    final currentPath = html.window.location.pathname;
    print('_updateBrowserUrl - Current path: $currentPath, Game path: $gamePath');
    
    // Check if we need to update the URL
    if (currentPath != null && !currentPath.endsWith(gamePath)) {
      // Use replaceState instead of pushState to avoid adding to history stack
      html.window.history.replaceState(null, '', gamePath);
      print('_updateBrowserUrl - Updated URL to: $gamePath');
    }
  }
  
  void _initializeStreams() {
    // Validate game ID
    if (widget.gameId.isEmpty) {
      print('ERROR: Game ID is empty! Cannot initialize streams.');
      return;
    }
    
    print('Initializing streams for game: ${widget.gameId}');
    
    // Initialize the streams with null check
    try {
      _gameStream = _gameService.getGameStream(widget.gameId);
      _scoresStream = _gameService.getGameScoresStream(widget.gameId);
      
      print('Streams initialized successfully');
      
      // Listen to score changes to update leaderboard
      _scoresStream?.listen((scores) {
        print('Received scores update - count: ${scores.length}');
        // Reset scores
        final newScores = <String, int>{};
        
        // Calculate total score for each player
        for (var score in scores) {
          newScores[score.userId] = (newScores[score.userId] ?? 0) + score.score;
        }
        
        setState(() {
          _playerScores = newScores;
        });
      }, onError: (error) {
        print('Error in scores stream: $error');
      });
      
      // Listen to game changes to update current question
      _gameStream?.listen((game) {
        print('Received game update - status: ${game?.status}');
        
        // Store the game data to check if we've received it
        if (game != null) {
          _receivedGame = game;
          
          // Cancel the timeout timer if we received game data
          if (_loadingTimer != null) {
            print('Cancelling timeout timer - received game data');
            _loadingTimer!.cancel();
            _loadingTimer = null;
          }
          
          // Trigger UI update if we've received game data
          if (_hasTimedOut) {
            print('Game data arrived after timeout - resetting timeout flag');
            setState(() {
              _hasTimedOut = false;
            });
          }
        }
        
        if (game != null && game.status == GameStatus.inProgress) {
          _loadCurrentQuestion(game);
        }
      }, onError: (error) {
        print('Error in game stream: $error');
      });
    } catch (e) {
      print('Error initializing streams: $e');
    }
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
    print('GameScreen build called');
    return Scaffold(
      appBar: const CommonAppBar(title: 'Quiz Game'),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          print('Auth state connection: ${authSnapshot.connectionState}, hasData: ${authSnapshot.hasData}, user: ${authSnapshot.data?.uid}');
          // Check if user is authenticated
          if (authSnapshot.connectionState == ConnectionState.active) {
            final user = authSnapshot.data;
            
            // If user is not logged in, show message directing to login button
            if (user == null) {
              // Save the current game URL for redirect after login
              final currentPath = html.window.location.pathname;
              if (currentPath != null) {
                html.window.sessionStorage['redirect_after_login'] = currentPath;
                print('Saved redirect path: $currentPath');
              }
              
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Please log in to access this game',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Use the login button in the top right corner of the screen',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.arrow_upward,
                      size: 32,
                      color: Colors.blue,
                    ),
                  ],
                ),
              );
            }
            
            // If user is logged in, continue with game content
            print('User authenticated: ${user.uid}, loading game content');
            
            // Create a local variable that combines both the stream and our direct game access
            return StreamBuilder<Game?>(
              stream: _gameStream,
              builder: (context, snapshot) {
                print('Game stream connection: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');
                
                // Handle errors first
                if (snapshot.hasError) {
                  print('Game stream error: ${snapshot.error}');
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                
                // Check for data regardless of connection state
                final game = snapshot.data ?? _receivedGame;
                
                // Only show loading indicator if we're still waiting for the initial connection
                // AND we don't have any data yet AND we haven't timed out
                if ((snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) 
                    && game == null && !_hasTimedOut) {
                  print('Game is still loading (initial connection)...');
                  return const Center(child: CircularProgressIndicator());
                }
                
                // Check for timeout
                if (_hasTimedOut) {
                  print('Loading timed out - displaying error message');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Game is taking too long to load.'),
                        const SizedBox(height: 16),
                        const Text('This might indicate the game does not exist or there was a connection issue.'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            html.window.location.href = '/games';
                          },
                          child: const Text('Return to Game Lobby'),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _hasTimedOut = false;
                              _initializeStreams();
                              
                              // Reset timeout timer
                              _loadingTimer?.cancel();
                              _loadingTimer = Timer(const Duration(seconds: 10), () {
                                print('Game loading timed out after retry');
                                setState(() {
                                  _hasTimedOut = true;
                                });
                              });
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                
                // If connection is active but we have no data, it means the game doesn't exist
                if (game == null) {
                  print('Game not found for ID: ${widget.gameId}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Game not found'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            html.window.location.href = '/games';
                          },
                          child: const Text('Return to Game Lobby'),
                        ),
                      ],
                    ),
                  );
                }
                
                // If we have data, show the appropriate screen based on game status
                print('Game loaded successfully - id: ${game.id}, status: ${game.status}');
                if (game.status == GameStatus.waiting) {
                  return _buildWaitingScreen(game);
                } else if (game.status == GameStatus.completed) {
                  return _buildGameCompletedScreen(game);
                } else {
                  return _buildGameInProgressScreen(game);
                }
              },
            );
          }
          
          // While checking authentication state
          return const Center(child: CircularProgressIndicator());
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
              html.window.location.href = '/game/${game.id}/lobby';
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
                  html.window.location.href = '/games';
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
