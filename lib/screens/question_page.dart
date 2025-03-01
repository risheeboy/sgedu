import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/question_card.dart';
import '../services/question_service.dart';
import '../models/question.dart';
import '../widgets/common_app_bar.dart';

class QuestionPage extends StatefulWidget {
  final String? initialQuestionId;
  final bool showAppBar;
  
  const QuestionPage({
    super.key, 
    this.initialQuestionId,
    this.showAppBar = false,
  });

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  final _questionService = QuestionService();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  String? _selectedSyllabus;
  String? _selectedSubject;
  List<String>? _syllabusFiles;
  bool _isLoading = false;
  List<Question>? _generatedQuestions;
  List<Question>? _existingQuestions;
  int _currentPage = 1;
  DocumentSnapshot? _lastDocument;
  static const int _pageSize = 1;

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
    _topicController.addListener(() => setState(() {}));
    
    // Check for initialQuestionId from constructor
    if (widget.initialQuestionId != null && widget.initialQuestionId!.isNotEmpty) {
      print('Loading question by ID from widget parameter: ${widget.initialQuestionId}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadQuestionById(widget.initialQuestionId!);
      });
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
      _generatedQuestions = null;
    });

    try {
      final questions = await _questionService.generateQuestions(
        _selectedSubject!,
        syllabus: _selectedSyllabus!,
        topic: _topicController.text.isNotEmpty ? _topicController.text : null,
      );
      setState(() {
        _generatedQuestions = questions;
        _existingQuestions = null;
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

  Future<void> _getExistingQuestions() async {
    print('Fetching existing questions for syllabus: $_selectedSyllabus, subject: $_selectedSubject, topic: ${_topicController.text}, page: $_currentPage, lastDocument: $_lastDocument');
    // Validate inputs
    if (_selectedSubject == null || _selectedSyllabus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a syllabus and subject'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Fetch questions, excluding those with existing feedback
    Query<Map<String, dynamic>> questionsQuery = FirebaseFirestore.instance
        .collection('questions')
        .where('syllabus', isEqualTo: _selectedSyllabus)
        .where('subject', isEqualTo: _selectedSubject);
    
    // Add topic filter if topic is provided
    if (_topicController.text.trim().isNotEmpty) {
      final normalizedTopic = _topicController.text.trim();
      questionsQuery = questionsQuery.where('topics', arrayContains: normalizedTopic);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {

      // Fetch IDs of questions with existing feedback (last 50)
      final feedbackQuery = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      final List<String> excludedQuestionIds = feedbackQuery.docs
          .map((doc) => doc['questionId'] as String)
          .where((id) => id.isNotEmpty) // Filter out empty IDs
          .toList();
      print("Excluded question IDs (last 50): $excludedQuestionIds");
      

      if (excludedQuestionIds.isNotEmpty) {
        questionsQuery = questionsQuery.where(FieldPath.documentId, whereNotIn: excludedQuestionIds);
      }
    }

    questionsQuery = questionsQuery.orderBy(FieldPath.documentId);
    if (_currentPage > 1 && _lastDocument != null) {
      print('Fetching existing questions: page $_currentPage, last document: ${_lastDocument}');
      questionsQuery = questionsQuery.startAfterDocument(_lastDocument!).limit(_pageSize);
    } else {
      questionsQuery = questionsQuery.limit(_pageSize);
    }

    setState(() {
      _isLoading = true;
      _generatedQuestions = null;
      _existingQuestions = null;
    });

    try {
      final snapshot = await questionsQuery.get();
      setState(() {
        _existingQuestions = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Question.fromJson(data);
        }).toList(); 
      });
      // Show snackbar if no questions found
      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new questions found'),
          ),
        );
      } else {
        _lastDocument = snapshot.docs.last;
        final questionId = _lastDocument!.id;
        print('Updating browser history state with question ID: $questionId');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load questions: ${e.toString()}'),
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
    if (_generatedQuestions != null && _generatedQuestions!.isNotEmpty) {//show generated questions
      return ListView.builder(
        itemCount: _generatedQuestions!.length,
        itemBuilder: (context, index) {
          final question = _generatedQuestions![index];
          return QuestionCard(
            question: question,
            index: index,
            topicController: _topicController,
          );
        },
      );
    } else if (_existingQuestions != null && _existingQuestions!.isNotEmpty) {//show existing questions
      return ListView.builder(
        itemCount: _existingQuestions!.length,
        itemBuilder: (context, index) {
          final question = _existingQuestions![index];
          return QuestionCard(
            question: question,
            index: index,
            topicController: _topicController,
          );
        },
      );
    } else {
      return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.showAppBar 
      ? Scaffold(
        appBar: CommonAppBar(
          title: 'Edu🦦Thingz',
          shareUrl: _existingQuestions != null && _existingQuestions!.isNotEmpty
              ? '/question/${_existingQuestions![0].id}'
              : null,
        ),
        body: _buildContent(),
      )
      : _buildContent();
  }
  
  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {//wide screen
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
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
                        ),
                        const SizedBox(width: 16),
                        if (_syllabusFiles != null)
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
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
                                if (value != null) {
                                  _lastDocument = null;
                                  _currentPage = 1;
                                  _getExistingQuestions();
                                }
                              },
                            ),
                          ),
                      ],
                    );
                  } else {//narrow screen
                    return Column(
                      children: [
                        DropdownButtonFormField<String>(
                          isExpanded: true,
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
                        if (_syllabusFiles != null)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
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
                              if (value != null) {
                                _lastDocument = null;
                                _currentPage = 1;
                                _getExistingQuestions();
                              }
                            },
                          ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              if (_selectedSubject != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _topicController,
                        onChanged: (value) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Topic (Optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 56, // Match text field height
                      child: ElevatedButton(
                        onPressed: () {
                          if (_isLoading || _topicController.text.trim().isEmpty) {
                            return null;
                          } else {
                            _lastDocument = null;
                            _currentPage = 1;
                            _getExistingQuestions();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                        ),
                        child: const Text('Go'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: () {
                    if (FirebaseAuth.instance.currentUser == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please login to generate questions'),
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
                      : const Text('Generate 10 new questions'),
                ),
              ],
              if (_generatedQuestions != null || _existingQuestions != null) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_generatedQuestions != null && _generatedQuestions!.isNotEmpty)
                      const Text(
                        'Generated Questions:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
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
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() => _currentPage -= 1);
                              _getExistingQuestions();
                            }
                          : null,
                      child: Text('← Previous'),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _currentPage += 1);
                        _getExistingQuestions();
                      },
                      child: Text('Next →'),
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
