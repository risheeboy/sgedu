import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game.dart';
import '../models/quiz.dart';
import '../services/game_service.dart';
import '../services/quiz_service.dart';
import '../widgets/common_app_bar.dart';
import 'package:go_router/go_router.dart';
import 'dart:js' as js;
import 'package:qr_flutter/qr_flutter.dart';

class GameLobbyScreen extends StatefulWidget {
  final String? gameId;
  
  const GameLobbyScreen({
    Key? key,
    this.gameId,
  }) : super(key: key);

  @override
  State<GameLobbyScreen> createState() => _GameLobbyScreenState();
}

class _GameLobbyScreenState extends State<GameLobbyScreen> {
  final GameService _gameService = GameService();
  final QuizService _quizService = QuizService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Stream<List<Game>>? _publicGamesStream;
  Stream<List<Game>>? _userGamesStream;
  Stream<Game?>? _currentGameStream;
  Stream<List<Quiz>>? _userQuizzesStream;
  
  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }
  
  void _initializeStreams() {
    // Initialize auth state listener
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        setState(() {
          _publicGamesStream = _gameService.getPublicGamesStream();
          _userGamesStream = _gameService.getUserGamesStream();
          _userQuizzesStream = _quizService.getUserQuizzesStream();
          
          if (widget.gameId != null) {
            _currentGameStream = _gameService.getGameStream(widget.gameId!);
          }
        });
      } else {
        // Redirect to login if not signed in
        context.go('/login');
      }
    });
  }
  
  Future<void> _createNewGame(String quizId) async {
    try {
      final gameId = await _gameService.createGame(quizId: quizId);
      // Navigate to the game screen using go_router
      if (mounted) {
        context.go('/game/$gameId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating game: $e')),
        );
      }
    }
  }
  
  Future<void> _joinGame(String gameId) async {
    try {
      await _gameService.joinGame(gameId);
      // Navigate to the game screen using go_router
      if (mounted) {
        context.go('/game/$gameId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining game: $e')),
        );
      }
    }
  }
  
  // Helper method to copy text to clipboard
  void _copyToClipboard(BuildContext context, String text) {
    try {
      // Execute JavaScript to handle clipboard copy
      js.context.callMethod('eval', ['''
        (function(text) {
          // Create textarea element
          var textarea = document.createElement('textarea');
          
          // Set value and styles
          textarea.value = text;
          textarea.style.position = 'fixed';
          textarea.style.opacity = '0';
          
          // Add to document, select text, and copy
          document.body.appendChild(textarea);
          textarea.select();
          
          // Copy the text
          document.execCommand('copy');
          
          // Clean up
          document.body.removeChild(textarea);
          
          return true;
        })("${text.replaceAll('"', '\\"')}")
      ''']);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game URL copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  void _showGameQRCode(BuildContext context, String gameId) {
    final gameUrl = '${Uri.base.origin}/#/game/$gameId';
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Game Invite QR Code',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: QrImageView(
                  data: gameUrl,
                  size: 240,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: 'Game Lobby'),
      body: StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.data == null) {
            return const Center(
              child: Text('Please sign in to access the game lobby'),
            );
          }
          
          // If a specific game ID is provided, show that game
          if (widget.gameId != null) {
            return _buildGameLobby();
          }
          
          // Otherwise show the list of games
          return _buildGamesList();
        },
      ),
    );
  }
  
  Widget _buildGameLobby() {
    return StreamBuilder<Game?>(
      stream: _currentGameStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
        
        // If game is in progress, redirect to game screen
        if (game.status == GameStatus.inProgress || game.status == GameStatus.completed) {
          Future.microtask(() {
            if (mounted) {
              context.go('/game/${game.id}');
            }
          });
          return const Center(child: CircularProgressIndicator());
        }
        
        // Show waiting room
        return Padding(
          padding: const EdgeInsets.all(16.0),
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
                        'Waiting for players',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('quizzes')
                            .doc(game.quizId)
                            .get(),
                        builder: (context, quizSnapshot) {
                          if (quizSnapshot.connectionState == ConnectionState.waiting) {
                            return const Text('Loading quiz info...');
                          }
                          
                          if (quizSnapshot.hasError || !quizSnapshot.hasData || !quizSnapshot.data!.exists) {
                            return const Text('Quiz information not available');
                          }
                          
                          final quizData = quizSnapshot.data!.data() as Map<String, dynamic>;
                          return Text('Quiz: ${quizData['name']}');
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${Uri.base.origin}/#/game/${game.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.content_copy, size: 16),
                            tooltip: 'Copy game URL',
                            onPressed: () {
                              final gameUrl = '${Uri.base.origin}/#/game/${game.id}';
                              _copyToClipboard(context, gameUrl);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code, size: 16),
                            tooltip: 'Show QR Code',
                            onPressed: () {
                              _showGameQRCode(context, game.id);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Players (${game.players.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...game.players.entries.map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.person),
                            const SizedBox(width: 8),
                            Text(
                              entry.value,
                              style: entry.key == game.hostId
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            ),
                            if (entry.key == game.hostId)
                              const Text(' (Host)', style: TextStyle(fontStyle: FontStyle.italic)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Only host can start the game
              if (game.hostId == _auth.currentUser?.uid)
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _gameService.startGame(game.id);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error starting game: $e')),
                      );
                    }
                  },
                  child: const Text('Start Game'),
                )
              else
                const Text('Waiting for host to start the game...'),
              
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  try {
                    await _gameService.leaveGame(game.id);
                    context.go('/games');
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error leaving game: $e')),
                    );
                  }
                },
                child: const Text('Leave Game'),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildGamesList() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a New Game',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            // Show user quizzes to create a game from
            StreamBuilder<List<Quiz>>(
              stream: _userQuizzesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                
                final quizzes = snapshot.data ?? [];
                
                if (quizzes.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('You haven\'t created any quizzes yet. Create a quiz first to start a game.'),
                    ),
                  );
                }
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select a quiz to create a game:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: quizzes.map((quiz) {
                        return ElevatedButton(
                          onPressed: () => _createNewGame(quiz.id),
                          child: Text(quiz.name),
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            Text(
              'Your Games',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Show user's active games
            StreamBuilder<List<Game>>(
              stream: _userGamesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                
                final games = snapshot.data ?? [];
                
                if (games.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('You are not participating in any games'),
                    ),
                  );
                }
                
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('quizzes')
                                        .doc(game.quizId)
                                        .get(),
                                    builder: (context, quizSnapshot) {
                                      if (quizSnapshot.connectionState == ConnectionState.waiting) {
                                        return const Text('Loading...');
                                      }
                                      
                                      if (quizSnapshot.hasError || !quizSnapshot.hasData || !quizSnapshot.data!.exists) {
                                        return const Text('Quiz not available');
                                      }
                                      
                                      final quizData = quizSnapshot.data!.data() as Map<String, dynamic>;
                                      final date = game.createdAt.toLocal();
                                      final dateStr = '${date.day}/${date.month}/${date.year.toString().substring(2)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: RichText(
                                              text: TextSpan(
                                                style: Theme.of(context).textTheme.bodyMedium,
                                                children: [
                                                  TextSpan(
                                                    text: quizData['name'],
                                                    style: Theme.of(context).textTheme.titleMedium,
                                                  ),
                                                  const TextSpan(text: '  '), // Space between name and date
                                                  TextSpan(
                                                    text: dateStr,
                                                    style: const TextStyle(color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${game.players.length} players',
                                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: Text('Status: ${game.status.toString().split('.').last}')),
                                if (game.status == GameStatus.completed)
                                  ElevatedButton(
                                    onPressed: () {
                                      context.go('/game/${game.id}');
                                    },
                                    child: const Text('Results'),
                                  ),
                                if (game.status != GameStatus.completed)
                                  ElevatedButton(
                                    onPressed: () {
                                      context.go('/game/${game.id}');
                                    },
                                    child: Text(
                                      game.status == GameStatus.inProgress
                                        ? 'Continue'
                                        : 'Join',
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${Uri.base.origin}/#/game/${game.id}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.content_copy, size: 16),
                                  tooltip: 'Copy game URL',
                                  onPressed: () {
                                    final gameUrl = '${Uri.base.origin}/#/game/${game.id}';
                                    _copyToClipboard(context, gameUrl);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code, size: 16),
                                  tooltip: 'Show QR Code',
                                  onPressed: () {
                                    _showGameQRCode(context, game.id);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            Text(
              'Public Games',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Show public available games
            StreamBuilder<List<Game>>(
              stream: _publicGamesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                
                final games = snapshot.data ?? [];
                
                if (games.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No public games available'),
                    ),
                  );
                }
                
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];
                    
                    // Skip if user is already in this game
                    if (game.players.containsKey(_auth.currentUser?.uid)) {
                      return const SizedBox.shrink();
                    }
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance
                                        .collection('quizzes')
                                        .doc(game.quizId)
                                        .get(),
                                    builder: (context, quizSnapshot) {
                                      if (quizSnapshot.connectionState == ConnectionState.waiting) {
                                        return const Text('Loading...');
                                      }
                                      
                                      if (quizSnapshot.hasError || !quizSnapshot.hasData || !quizSnapshot.data!.exists) {
                                        return const Text('Quiz not available');
                                      }
                                      
                                      final quizData = quizSnapshot.data!.data() as Map<String, dynamic>;
                                      final date = game.createdAt.toLocal();
                                      final dateStr = '${date.day}/${date.month}/${date.year.toString().substring(2)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: RichText(
                                              text: TextSpan(
                                                style: Theme.of(context).textTheme.bodyMedium,
                                                children: [
                                                  TextSpan(
                                                    text: quizData['name'],
                                                    style: Theme.of(context).textTheme.titleMedium,
                                                  ),
                                                  const TextSpan(text: '  '), // Space between name and date
                                                  TextSpan(
                                                    text: dateStr,
                                                    style: const TextStyle(color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${game.players.length} players',
                                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text('Status: ${game.status.toString().split('.').last}'),
                                if (game.status != GameStatus.completed)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: ElevatedButton(
                                      onPressed: () => _joinGame(game.id),
                                      child: Text(
                                        game.status == GameStatus.inProgress
                                          ? 'Spectate'
                                          : 'Join'
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${Uri.base.origin}/#/game/${game.id}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.content_copy, size: 16),
                                  tooltip: 'Copy game URL',
                                  onPressed: () {
                                    final gameUrl = '${Uri.base.origin}/#/game/${game.id}';
                                    _copyToClipboard(context, gameUrl);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code, size: 16),
                                  tooltip: 'Show QR Code',
                                  onPressed: () {
                                    _showGameQRCode(context, game.id);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
