import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/game_lobby_screen.dart';
import '../screens/game_screen.dart';
import '../screens/question_page.dart';
import '../screens/quiz_screen.dart';
import '../widgets/common_app_bar.dart';
import '../services/user_service.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = 
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Sign in with Google handler function
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

/// Sign out handler function
Future<void> signOut() async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (error) {
    print('Sign-out error: $error');
  }
}

/// App router configuration
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  debugLogDiagnostics: true,
  redirect: (context, state) async {
    final user = FirebaseAuth.instance.currentUser;
    
    // If user signs in, update last login
    if (user != null) {
      await UserService.updateLastLogin(user.uid);
    }
    
    // No redirects needed currently, but could add authenticated route protection here
    return null;
  },
  routes: [
    // Home route
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        appBar: CommonAppBar(
          title: 'Edu🦦Thingz',
          shareUrl: Uri.base.toString(),
          customSignIn: signInWithGoogle,
          customSignOut: signOut,
        ),
        body: const QuestionPage(),
      ),
    ),
    
    // Question route
    GoRoute(
      path: '/question/:questionId',
      builder: (context, state) => QuestionPage(
        initialQuestionId: state.pathParameters['questionId'],
        showAppBar: true,
      ),
    ),
    
    // Quiz route
    GoRoute(
      path: '/quiz/:quizId',
      builder: (context, state) {
        final sourceQuestionId = state.uri.queryParameters['from'];
        return QuizScreen(
          quizId: state.pathParameters['quizId']!,
          sourceQuestionId: sourceQuestionId,
        );
      },
    ),
    
    // Games lobby route
    GoRoute(
      path: '/games',
      builder: (context, state) => const GameLobbyScreen(),
    ),
    
    // Game lobby route with specific game ID
    GoRoute(
      path: '/game/:gameId/lobby',
      builder: (context, state) => GameLobbyScreen(
        gameId: state.pathParameters['gameId'],
      ),
    ),
    
    // Game screen route
    GoRoute(
      path: '/game/:gameId',
      builder: (context, state) => GameScreen(
        gameId: state.pathParameters['gameId']!,
      ),
    ),
    
    // Login route - redirects to home after sign-in
    GoRoute(
      path: '/login',
      builder: (context, state) => Scaffold(
        appBar: const CommonAppBar(
          title: 'Sign In',
          showQuizButton: false,
          showGameButton: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Please sign in to continue', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
                onPressed: () async {
                  await signInWithGoogle();
                  if (context.mounted) {
                    context.go('/');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: const CommonAppBar(title: 'Page Not Found'),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Page not found!',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);
