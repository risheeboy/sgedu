import 'package:flutter/material.dart';
import '../theme/theme_service.dart';
import '../widgets/common_app_bar.dart';
import '../routing/router.dart';
import '../widgets/styled_card.dart';
import '../widgets/quiz_list_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeServiceWidget = ThemeServiceWidget.of(context);
    
    return Scaffold(
      appBar: CommonAppBar(
        title: 'Settings',
        customSignIn: signInWithGoogle,
        customSignOut: signOut,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SectionTitle(title: 'Appearance'),
          StyledCard(
            child: _buildThemeSelector(context, themeServiceWidget),
          ),
          const SizedBox(height: 24),
          SectionTitle(title: 'Study Materials'),
          StyledCard(
            child: _buildQuizManagement(context),
          ),
          const SizedBox(height: 24),
          SectionTitle(title: 'About'),
          StyledCard(
            child: Column(
              children: [
                _buildAboutItem(
                  context,
                  title: 'Edu🦦Thingz',
                  subtitle: 'Help students with exam preparation',
                  icon: Icons.info_outline,
                ),
                const Divider(),
                _buildAboutItem(
                  context,
                  title: 'Version',
                  subtitle: '0.1.0 Alpha',
                  icon: Icons.new_releases_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context, ThemeServiceWidget themeServiceWidget) {
    return ListTile(
      title: const Text('Theme'),
      subtitle: const Text('Choose your preferred theme'),
      leading: const Icon(Icons.palette_outlined),
      trailing: DropdownButton<AppThemeMode>(
        value: themeServiceWidget.themeService.themeMode,
        onChanged: (AppThemeMode? newMode) {
          if (newMode != null) {
            themeServiceWidget.onThemeChanged(newMode);
          }
        },
        items: const [
          DropdownMenuItem(
            value: AppThemeMode.system,
            child: Text('System'),
          ),
          DropdownMenuItem(
            value: AppThemeMode.light,
            child: Text('Light'),
          ),
          DropdownMenuItem(
            value: AppThemeMode.dark,
            child: Text('Dark'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizManagement(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user != null) {
            return ListTile(
              title: const Text('Manage Quizzes'),
              subtitle: const Text('Manage the quizzes you have created'),
              leading: const Icon(Icons.quiz),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) => const QuizListDialog(),
                );
              },
            );
          }
        }
        return const ListTile(
          title: Text('Your Quizzes'),
          subtitle: Text('Sign in to manage your quizzes'),
          leading: Icon(Icons.quiz, color: Colors.grey),
          enabled: false,
        );
      },
    );
  }

  Widget _buildAboutItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      leading: Icon(icon),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
