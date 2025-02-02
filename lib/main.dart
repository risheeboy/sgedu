import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/question_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Education App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const QuestionGeneratorPage(),
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
  bool _showAnswers = false;
  List<Question>? _questions;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Generator'),
      ),
      body: Padding(
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
                  onPressed: _isLoading ? null : _generateQuestions,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Generate Questions'),
                ),
                if (_questions != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Generated Questions:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showAnswers = !_showAnswers;
                          });
                        },
                        icon: Icon(_showAnswers
                            ? Icons.visibility_off
                            : Icons.visibility),
                        label:
                            Text(_showAnswers ? 'Hide Answers' : 'Show Answers'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _questions!.length,
                      itemBuilder: (context, index) {
                        final question = _questions![index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Question ${index + 1}:',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  question.question,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                if (_showAnswers) ...[
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Answer:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(question.correctAnswer),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Explanation:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(question.explanation),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
