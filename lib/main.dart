import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'firebase_options.dart';
import 'services/question_service.dart';
import 'services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'package:flutter/services.dart';
import 'widgets/question_card.dart';

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
      // Existing login logic
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
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Edu🦦Thingz'),
          actions: [
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
        body: const QuestionGeneratorPage(),
      ),
    );
  }
}

class QuestionGeneratorPage extends StatefulWidget {
  const QuestionGeneratorPage({super.key});

  @override
  State<QuestionGeneratorPage> createState() => _QuestionGeneratorPageState();
}

class _QuestionGeneratorPageState extends State<QuestionGeneratorPage> {
  final _questionService = QuestionService();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  String? _selectedSyllabus;
  String? _selectedSubject;
  List<String>? _syllabusFiles;
  bool _isLoading = false;
  List<Question>? _questions;
  List<Question>? _existingQuestions;
  int _currentPage = 1;
  int _totalPages = 1;

  // Add syllabus options
  final List<String> _syllabusOptions = [
    'Singapore GCE A-Level',
    'Singapore GCE O-Level'
  ];

  // Method to get syllabus files based on selection
  void _updateSyllabusFiles() {
    setState(() {
      if (_selectedSyllabus == 'Singapore GCE A-Level') {
        _syllabusFiles = [
          'Biology.md',
          'Chemistry.md',
          'China Studies in English.md',
          'Computing.md',
          'Economics.md',
          'Further Mathematics.md',
          'Geography.md',
          'History.md',
          'Literature in English.md',
          'Mathematics.md',
          'Physics.md',
          'Principles of Accounting.md'
        ];
      } else if (_selectedSyllabus == 'Singapore GCE O-Level') {
        _syllabusFiles = [
          'Biology.md',
          'Chemistry.md',
          'Mathematics.md',
          'Physics.md'
        ];
      } else {
        _syllabusFiles = null;
      }
      _selectedSubject = null; // Reset subject when syllabus changes
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleDeepLink());
  }

  void _handleDeepLink() {
    final uri = Uri.parse(html.window.location.href);
    final questionId = uri.queryParameters['questionId'];
    if (questionId != null && questionId.isNotEmpty) {
      _loadQuestionById(questionId);
    }
  }

  Future<void> _loadQuestionById(String id) async {
    setState(() => _isLoading = true);
    try {
      final question = await _questionService.getQuestionById(id);
      setState(() {
        _selectedSyllabus = question.syllabus;
      });
      _updateSyllabusFiles();
      setState(() {
        _selectedSubject = question.subject;
        _existingQuestions = [question];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading question: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _generateQuestions() async {
    // Validate inputs
    if (_selectedSubject == null ||
        _selectedSyllabus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a syllabus and subject'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _questions = null;
    });

    try {
      final questions = await _questionService.generateQuestions(
        _selectedSubject!,
        syllabus: _selectedSyllabus!,
        topic: _topicController.text.isNotEmpty ? _topicController.text : null,
      );
      setState(() {
        _questions = questions;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating questions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getExistingQuestions({int? page}) async {
    // Validate inputs
    if (_selectedSubject == null ||
        _selectedSyllabus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a syllabus and subject'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _existingQuestions = null;
    });

    try {
      final questions = await _questionService.getQuestions(
        syllabus: _selectedSyllabus!,
        subject: _selectedSubject!,
        topic: _topicController.text.isNotEmpty ? _topicController.text : null,
        limit: 1,
        page: page ?? _currentPage
      );
      
      setState(() {
        _existingQuestions = questions;
        _totalPages = questions.isNotEmpty ? _currentPage + 1 : _totalPages;
      });
      if (questions.isNotEmpty && questions[0].id != null) {
        html.window.history.replaceState(null, '', '?questionId=${questions[0].id}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting existing questions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildQuestionsList() {
    if (_questions != null && _questions!.isNotEmpty) {
      return ListView.builder(
        itemCount: _questions!.length,
        itemBuilder: (context, index) {
          final question = _questions![index];
          return QuestionCard(question: question, index: index);
        },
      );
    } else if (_existingQuestions != null && _existingQuestions!.isNotEmpty) {
      return ListView.builder(
        itemCount: _existingQuestions!.length,
        itemBuilder: (context, index) {
          final question = _existingQuestions![index];
          return QuestionCard(question: question, index: index);
        },
      );
    } else {
      return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Syllabus Dropdown
              DropdownButtonFormField<String>(
                value: _selectedSyllabus,
                decoration: const InputDecoration(
                  labelText: 'Syllabus',
                  border: OutlineInputBorder(),
                ),
                items: _syllabusOptions
                    .map((syllabus) => DropdownMenuItem(
                          value: syllabus,
                          child: Text(syllabus),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSyllabus = value!;
                    _updateSyllabusFiles();
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // Subject Dropdown (only show when syllabus is selected)
              if (_syllabusFiles != null) 
                DropdownButtonFormField<String>(
                  value: _selectedSubject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                  items: _syllabusFiles!
                      .map((file) => DropdownMenuItem(
                            value: file.replaceAll('.md', ''),
                            child: Text(file.replaceAll('.md', '')),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSubject = value;
                    });
                  },
                ),
              const SizedBox(height: 16),

              // Optional Topic Input
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: () {
                  if (FirebaseAuth.instance.currentUser == null) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Login Required'),
                        content: const Text('Please login to generate questions.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    _generateQuestions();
                  }
                },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Generate Questions'),
              ),
              ElevatedButton(
                onPressed: _isLoading ? null : _getExistingQuestions,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Show Questions'),
              ),
              if (_questions != null || _existingQuestions != null) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_questions != null && _questions!.isNotEmpty)
                      const Text(
                        'Generated:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (_existingQuestions != null && _existingQuestions!.isNotEmpty)
                      const Text(
                        'Questions:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildQuestionsList(),
                ),
              ],
              if (_existingQuestions != null && _existingQuestions!.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Question $_currentPage', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _currentPage < _totalPages
                          ? () {
                              setState(() => _currentPage += 1);
                              _getExistingQuestions();
                            }
                          : null,
                      child: Text('Next →'),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() => _currentPage -= 1);
                              _getExistingQuestions();
                            }
                          : null,
                      child: Text('← Previous'),
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
