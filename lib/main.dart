// Import dart:math for the min function
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
import 'services/quiz_service.dart';
import 'models/quiz.dart';

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
      onGenerateRoute: (settings) {
        // Handle quiz route with ID parameter
        if (settings.name?.startsWith('/quiz/') ?? false) {
          print('Quiz route: ${settings.name}');
          final quizId = settings.name!.substring(6); // Remove '/quiz/' prefix
          print('Quiz ID: $quizId');
          return MaterialPageRoute(
            builder: (context) => QuizScreen(quizId: quizId),
          );
        }
        
        // Default route
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Edu🦦Thingz'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share',
                  onPressed: () {
                    final currentUrl = html.window.location.href;
                    try {
                      // Try using Web Share API
                      html.window.navigator.share({'url': currentUrl});
                    } catch (e) {
                      // Fallback to clipboard
                      html.window.navigator.clipboard?.writeText(currentUrl);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.active) {
                      final user = snapshot.data;
                      if (user != null) {
                        return IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Logout',
                          onPressed: signOut,
                        );
                      } else {
                        return IconButton(
                          icon: const Icon(Icons.login),
                          tooltip: 'Login with Google',
                          onPressed: signInWithGoogle,
                        );
                      }
                    }
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                ),
              ],
            ),
            body: Row(
              children: [
                // Main content area (Question Page) - takes 70% of the width
                const Expanded(
                  flex: 7,
                  child: QuestionPage(),
                ),
                // Right sidebar with quizzes - takes 30% of the width
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Your Quizzes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Expanded(
                          child: StreamBuilder<User?>(
                            stream: FirebaseAuth.instance.authStateChanges(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.active) {
                                final user = snapshot.data;
                                if (user != null) {
                                  return StreamBuilder<List<Quiz>>(
                                    stream: QuizService().getUserQuizzesStream(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        final quizzes = snapshot.data!;
                                        if (quizzes.isEmpty) {
                                          return const Center(
                                            child: Text('No quizzes yet'),
                                          );
                                        }
                                        return ListView.builder(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          itemCount: quizzes.length,
                                          itemBuilder: (context, index) {
                                            final quiz = quizzes[index];
                                            return Card(
                                              margin: const EdgeInsets.only(bottom: 8.0),
                                              child: ListTile(
                                                title: Text(
                                                  quiz.name,
                                                  style: Theme.of(context).textTheme.bodyMedium,
                                                ),
                                                subtitle: Text(
                                                  '${quiz.questionIds.length} questions',
                                                  style: Theme.of(context).textTheme.bodySmall,
                                                ),
                                                onTap: () {
                                                  Navigator.pushNamed(
                                                    context,
                                                    '/quiz/${quiz.id}',
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                  );
                                }
                                return const Center(
                                  child: Text('Sign in to view your quizzes'),
                                );
                              }
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
