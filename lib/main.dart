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
  String? _selectedGrade;
  String? _selectedSyllabus;
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
          'Computing.md',
          'Further-Mathematics.md',
          'Mathematics.md',
          'Physics.md',
          'Principles-of-Accounting.md'
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
    });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _generateQuestions() async {
    // Validate inputs
    if (_subjectController.text.isEmpty ||
        _selectedGrade == null ||
        _selectedSyllabus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
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
        _subjectController.text,
        _selectedGrade ?? '',
        syllabus: _selectedSyllabus!,
        syllabusFiles: _syllabusFiles ?? [],
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
                if (_syllabusFiles != null) ...[
                  const Text(
                    'Available Subjects:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _syllabusFiles!
                        .map((file) => Chip(
                              label: Text(file.replaceAll('.md', '')),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedGrade,
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(12, (index) => (index + 1).toString())
                      .map((grade) => DropdownMenuItem(
                            value: grade,
                            child: Text('Grade $grade'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedGrade = value;
                    });
                  },
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
