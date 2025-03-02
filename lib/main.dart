import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'routing/router.dart';
import 'services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize theme service
  final themeService = ThemeService();
  await themeService.init();
  
  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user != null) {
      await UserService.updateLastLogin(user.uid);
    }
  });
  
  runApp(MyApp(themeService: themeService));
}

class MyApp extends StatefulWidget {
  final ThemeService themeService;
  
  const MyApp({super.key, required this.themeService});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }
  
  void _handleThemeChange(AppThemeMode mode) {
    setState(() {
      // Update UI after theme changes
    });
    widget.themeService.setThemeMode(mode);
  }
  
  @override
  Widget build(BuildContext context) {
    return ThemeServiceWidget(
      themeService: widget.themeService,
      onThemeChanged: _handleThemeChange,
      child: MaterialApp.router(
        title: 'Edu🦦Thingz',
        theme: widget.themeService.lightTheme,
        darkTheme: widget.themeService.darkTheme,
        themeMode: widget.themeService.getFlutterThemeMode(),
        routerConfig: appRouter,
      ),
    );
  }
}
