import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'dart:js' as js;

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? additionalActions;
  final String? shareUrl;
  final Function? customSignIn;
  final Function? customSignOut;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const CommonAppBar({
    Key? key, 
    this.title = 'Edu🦦Thingz',
    this.additionalActions,
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
      // Use leading if provided, otherwise show the otter logo with home navigation
      leading: leading ?? IconButton(
        icon: const Text(
          '🦦',
          style: TextStyle(fontSize: 24),
        ),
        tooltip: 'Home',
        onPressed: () {
          // Navigate to the landing page
          context.go('/');
        },
      ),
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: [
        // Additional actions specific to each screen
        if (additionalActions != null) ...additionalActions!,
        
        // Game lobby button
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.active) {
              final user = snapshot.data;
              return IconButton(
                icon: const Icon(Icons.games),
                tooltip: user != null ? 'Game Lobby' : 'Sign in to play games',
                onPressed: () {
                  if (user != null) {
                    context.go('/games');
                  } else {
                    // Show sign-in dialog or redirect to sign-in page
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Sign In Required'),
                          content: const Text('You need to sign in to access the game lobby.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                if (customSignIn != null) {
                                  customSignIn!();
                                } else {
                                  context.go('/signin');
                                }
                              },
                              child: const Text('Sign In'),
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
              );
            }
            return const SizedBox.shrink(); // Only during connection state check
          },
        ),

        // Settings button
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            context.go('/settings');
          },
        ),
          
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
