import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'dart:js' as js;
import 'quiz_list_dialog.dart';

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? additionalActions;
  final bool showQuizButton;
  final bool showGameButton;
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
    this.showGameButton = true,
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
          
        // Game lobby button - only if showGameButton is true
        if (showGameButton)
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                final user = snapshot.data;
                if (user != null) {
                  return IconButton(
                    icon: const Icon(Icons.games),
                    tooltip: 'Game Lobby',
                    onPressed: () {
                      context.go('/games');
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
              if (shareUrl == null) return;
              
              try {
                // Try using Web Share API if available
                if (js.context.hasProperty('navigator') && 
                    js.context['navigator'].hasProperty('share')) {
                  js.context['navigator'].callMethod('share', [js.JsObject.jsify({'url': shareUrl})]);
                } else {
                  // Fallback to clipboard
                  _copyToClipboard(context, shareUrl!);
                }
              } catch (e) {
                // Fallback to clipboard
                _copyToClipboard(context, shareUrl!);
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
                      context.go('/login');
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

  // Helper method to copy text to clipboard
  void _copyToClipboard(BuildContext context, String text) {
    try {
      // Execute JavaScript to handle clipboard copy
      js.context.callMethod('eval', ['''
        (function(text) {
          // Create textarea element
          var textarea = document.createElement('textarea');
          
          // Set value and styles
          textarea.value = text;
          textarea.style.position = 'fixed';
          textarea.style.opacity = '0';
          
          // Add to document, select text, and copy
          document.body.appendChild(textarea);
          textarea.select();
          
          // Copy the text
          document.execCommand('copy');
          
          // Clean up
          document.body.removeChild(textarea);
          
          return true;
        })("${text.replaceAll('"', '\\"')}")
      ''']);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
