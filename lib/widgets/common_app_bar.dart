import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'quiz_list_dialog.dart';

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? additionalActions;
  final bool showQuizButton;
  final String? shareUrl;
  final Function? customSignIn;
  final Function? customSignOut;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const CommonAppBar({
    Key? key, 
    this.title = 'Edu🦦Thingz',
    this.additionalActions,
    this.showQuizButton = true,
    this.shareUrl,
    this.customSignIn,
    this.customSignOut,
    this.leading,
    this.automaticallyImplyLeading = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: [
        // Quizzes dropdown button - only if showQuizButton is true
        if (showQuizButton)
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                final user = snapshot.data;
                if (user != null) {
                  return IconButton(
                    icon: const Icon(Icons.quiz),
                    tooltip: 'Your Quizzes',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) => const QuizListDialog(),
                      );
                    },
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
          
        // Additional actions specific to each screen
        if (additionalActions != null) ...additionalActions!,
        
        // Share button - only if shareUrl is provided
        if (shareUrl != null)
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {
              try {
                // Try using Web Share API
                html.window.navigator.share({'url': shareUrl});
              } catch (e) {
                // Fallback to clipboard
                final textarea = html.TextAreaElement();
                textarea.value = shareUrl;
                html.document.body!.append(textarea);
                textarea.select();
                html.document.execCommand('copy');
                textarea.remove();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          
        // Login/Logout button
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.active) {
              final user = snapshot.data;
              if (user != null) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () {
                    if (customSignOut != null) {
                      customSignOut!();
                    } else {
                      FirebaseAuth.instance.signOut();
                    }
                  },
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Login with Google',
                  onPressed: () {
                    if (customSignIn != null) {
                      customSignIn!();
                    } else {
                      // Default login logic
                      Navigator.pushNamed(context, '/login');
                    }
                  },
                );
              }
            }
            return const Center(
              child: CircularProgressIndicator(),
            );
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
