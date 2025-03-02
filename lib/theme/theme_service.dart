import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system,
  light,
  dark,
}

class ThemeService {
  static const String _themeModeKey = 'theme_mode';
  
  // Singleton instance
  static final ThemeService _instance = ThemeService._internal();
  
  factory ThemeService() => _instance;
  
  ThemeService._internal();
  
  // Current theme mode (defaulting to system)
  AppThemeMode _currentThemeMode = AppThemeMode.system;
  
  // Get the current theme mode
  AppThemeMode get themeMode => _currentThemeMode;
  
  // Convert AppThemeMode to Flutter's ThemeMode
  ThemeMode getFlutterThemeMode() {
    switch (_currentThemeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
  
  // Initialize the theme service
  Future<void> init() async {
    await _loadThemeMode();
  }
  
  // Set the theme mode and save to SharedPreferences
  Future<void> setThemeMode(AppThemeMode mode) async {
    _currentThemeMode = mode;
    await _saveThemeMode();
  }
  
  // Check if dark mode is active
  bool get isDarkMode {
    if (_currentThemeMode == AppThemeMode.system) {
      final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _currentThemeMode == AppThemeMode.dark;
  }
  
  // Load theme mode from SharedPreferences
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeIndex = prefs.getInt(_themeModeKey);
      if (themeModeIndex != null && themeModeIndex < AppThemeMode.values.length) {
        _currentThemeMode = AppThemeMode.values[themeModeIndex];
      }
    } catch (e) {
      print('Error loading theme mode: $e');
    }
  }
  
  // Save theme mode to SharedPreferences
  Future<void> _saveThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeModeKey, _currentThemeMode.index);
    } catch (e) {
      print('Error saving theme mode: $e');
    }
  }
  
  // Light theme
  ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Colors.blue,
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // Dark theme
  ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Colors.lightBlueAccent,
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

// ThemeServiceWidget - InheritedWidget to make the theme service available through the widget tree
class ThemeServiceWidget extends InheritedWidget {
  final ThemeService themeService;
  final Function(AppThemeMode) onThemeChanged;

  const ThemeServiceWidget({
    Key? key,
    required this.themeService,
    required this.onThemeChanged,
    required Widget child,
  }) : super(key: key, child: child);

  static ThemeServiceWidget of(BuildContext context) {
    final ThemeServiceWidget? result = context.dependOnInheritedWidgetOfExactType<ThemeServiceWidget>();
    assert(result != null, 'No ThemeServiceWidget found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeServiceWidget oldWidget) {
    return themeService.themeMode != oldWidget.themeService.themeMode;
  }
}
