import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'widgets/question_card.dart';
import 'services/question_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/user_service.dart';
import 'models/question.dart';
import 'screens/question_page.dart';
import 'screens/quiz_screen.dart';
import 'screens/game_lobby_screen.dart';
import 'screens/game_screen.dart';
import 'services/quiz_service.dart';
import 'services/game_service.dart';
import 'models/quiz.dart';
import 'models/game.dart';
import 'widgets/quiz_list_dialog.dart';
import 'widgets/common_app_bar.dart';

Future<void> signInWithGoogle() async {
  final GoogleAuthProvider googleProvider = GoogleAuthProvider();
  googleProvider.setCustomParameters({
    'client_id': '350183278922-mjn0ne7o52dqumoc610s552s5at1t35s.apps.googleusercontent.com'
  });
  try {
    await FirebaseAuth.instance.signInWithPopup(googleProvider);
  } catch (error) {
    print('Google sign-in error: $error');
  }
}

Future<void> signOut() async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (error) {
    print('Sign-out error: $error');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user != null) {
      await UserService.updateLastLogin(user.uid);
    }
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edu🦦Thingz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      initialRoute: '/',
      onGenerateInitialRoutes: (String initialRoute) {
        print('Initial route: $initialRoute');
        // For web, get the path from window.location.pathname
        final currentPath = html.window.location.pathname;
        print('Current path from window.location: $currentPath');
        
        if (currentPath != null && currentPath.isNotEmpty && currentPath != '/') {
          if (currentPath.startsWith('/quiz/')) {
            final quizId = currentPath.substring(6); // Remove '/quiz/' prefix
            print('Initial Quiz route detected: $quizId');
            return [
              MaterialPageRoute(
                builder: (context) => QuizScreen(quizId: quizId),
              )
            ];
          } else if (currentPath.startsWith('/question/')) {
            final questionId = currentPath.substring(10); // Remove '/question/' prefix
            print('Initial Question route detected: $questionId');
            return [
              MaterialPageRoute(
                builder: (context) => QuestionPage(
                  initialQuestionId: questionId,
                  showAppBar: true,
                ),
              )
            ];
          } else if (currentPath.startsWith('/game/')) {
            // Check if it's a game lobby or game screen
            if (currentPath.endsWith('/lobby')) {
              final gameId = currentPath.substring(6, currentPath.length - 6); // Remove '/game/' prefix and '/lobby' suffix
              print('Initial Game Lobby route detected: $gameId');
              return [
                MaterialPageRoute(
                  builder: (context) => GameLobbyScreen(gameId: gameId),
                )
              ];
            } else {
              final gameId = currentPath.substring(6); // Remove '/game/' prefix
              print('Initial Game route detected: $gameId');
              return [
                MaterialPageRoute(
                  builder: (context) => GameScreen(gameId: gameId),
                )
              ];
            }
          } else if (currentPath == '/games') {
            print('Initial Games Lobby route detected');
            return [
              MaterialPageRoute(
                builder: (context) => const GameLobbyScreen(),
              )
            ];
          }
        }
        
        // Default initial route
        return [
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: CommonAppBar(
                title: 'Edu🦦Thingz',
                shareUrl: html.window.location.href,
                customSignIn: signInWithGoogle,
                customSignOut: signOut,
              ),
              body: const QuestionPage(),
            ),
          )
        ];
      },
      onGenerateRoute: (settings) {
        // Handle quiz route with ID parameter
        if (settings.name?.startsWith('/quiz/') ?? false) {
          print('Quiz route: ${settings.name}');
          final quizId = settings.name!.substring(6); // Remove '/quiz/' prefix
          
          // Extract question ID from the URL if the user is navigating from a question
          String? sourceQuestionId;
          final currentPath = html.window.location.pathname;
          if (currentPath?.contains('/question/') ?? false) {
            try {
              // Extract question ID from path
              final questionIdMatch = RegExp(r'/question/([^/]+)').firstMatch(currentPath!);
              if (questionIdMatch != null && questionIdMatch.groupCount >= 1) {
                sourceQuestionId = questionIdMatch.group(1);
                print('Navigating to quiz from question ID: $sourceQuestionId');
              }
            } catch (e) {
              print('Error extracting question ID: $e');
            }
          }
          
          print('Quiz ID: $quizId');
          return MaterialPageRoute(
            builder: (context) => QuizScreen(
              quizId: quizId,
              sourceQuestionId: sourceQuestionId,
            ),
          );
        }
        
        // Handle question route with ID parameter (path-based format)
        if (settings.name?.startsWith('/question/') ?? false) {
          print('Question route: ${settings.name}');
          final questionId = settings.name!.substring(10); // Remove '/question/' prefix
          print('Question ID: $questionId');
          return MaterialPageRoute(
            builder: (context) => QuestionPage(
              initialQuestionId: questionId,
              showAppBar: true,
            ),
          );
        }
        
        // Handle game routes
        if (settings.name?.startsWith('/game/') ?? false) {
          print('Game route: ${settings.name}');
          // Check if it's a game lobby or game screen
          if (settings.name!.endsWith('/lobby')) {
            final gameId = settings.name!.substring(6, settings.name!.length - 6); // Remove '/game/' prefix and '/lobby' suffix
            print('Game Lobby ID: $gameId');
            return MaterialPageRoute(
              builder: (context) => GameLobbyScreen(gameId: gameId),
            );
          } else {
            final gameId = settings.name!.substring(6); // Remove '/game/' prefix
            print('Game ID: $gameId');
            return MaterialPageRoute(
              builder: (context) => GameScreen(gameId: gameId),
            );
          }
        }
        
        // Handle games lobby route
        if (settings.name == '/games') {
          print('Games Lobby route');
          return MaterialPageRoute(
            builder: (context) => const GameLobbyScreen(),
          );
        }
        
        // Default route
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: CommonAppBar(
              title: 'Edu🦦Thingz',
              shareUrl: html.window.location.href,
              customSignIn: signInWithGoogle,
              customSignOut: signOut,
            ),
            body: const QuestionPage(),
          ),
        );
      },
    );
  }
}
