import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/quiz.dart';
import '../services/quiz_service.dart';

class QuizListDialog extends StatelessWidget {
  const QuizListDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 300,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Quizzes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: StreamBuilder<List<Quiz>>(
                stream: QuizService().getUserQuizzesStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final quizzes = snapshot.data!;
                    if (quizzes.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No quizzes yet'),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: quizzes.length,
                      itemBuilder: (context, index) {
                        final quiz = quizzes[index];
                        return ListTile(
                          title: Text(quiz.name),
                          subtitle: Text('${quiz.questionIds.length} questions'),
                          onTap: () {
                            Navigator.pop(context); // Close dialog
                            context.go('/quiz/${quiz.id}');
                          },
                        );
                      },
                    );
                  }
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
