import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class QuestionCard extends StatefulWidget {
  final dynamic question;
  final int index;

  const QuestionCard({Key? key, required this.question, required this.index}) : super(key: key);

  @override
  _QuestionCardState createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  bool _showAnswers = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${widget.index + 1}:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.question.question,
              style: const TextStyle(fontSize: 16),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAnswers = !_showAnswers;
                  });
                },
                icon: Icon(_showAnswers ? Icons.visibility_off : Icons.visibility),
                label: Text(_showAnswers ? 'Hide Answers' : 'Show Answers'),
              ),
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
              MarkdownBody(
                data: widget.question.correctAnswer,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14.0),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Explanation:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
              const SizedBox(height: 8),
              MarkdownBody(
                data: widget.question.explanation,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14.0),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
