import 'package:material_ui/material_ui.dart';

import 'data/app_database.dart';
import 'models/student_profile.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() {
  runApp(const ClassWorkPulseApp());
}

class ClassWorkPulseApp extends StatelessWidget {
  const ClassWorkPulseApp({super.key, this.database});

  /// An already opened database, used by tests. The app opens its own.
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClassWorkPulse',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _AppRoot(database: database),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF00796B),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

/// Opens the database, then shows onboarding on first launch or the main app
/// once a student name has been saved.
class _AppRoot extends StatefulWidget {
  const _AppRoot({this.database});

  final AppDatabase? database;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  AppDatabase? _database;
  List<StudentProfile> _profiles = const [];
  int? _selectedStudentId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final database = widget.database ?? await AppDatabase.open();
      final profiles = await database.profiles();
      if (!mounted) return;
      setState(() {
        _database = database;
        _profiles = profiles;
        _selectedStudentId = profiles.isEmpty ? null : profiles.first.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _saveProfile(StudentProfile profile) async {
    final saved = await _database!.saveProfile(profile);
    await _refreshProfiles(saved.id);
  }

  Future<void> _addProfile(StudentProfile profile) async {
    final saved = await _database!.saveProfile(profile, asNew: true);
    await _refreshProfiles(saved.id);
  }

  Future<void> _refreshProfiles(int? selectedId) async {
    if (!mounted) return;
    final profiles = await _database!.profiles();
    setState(() {
      _profiles = profiles;
      _selectedStudentId = selectedId;
    });
  }

  void _selectStudent(int id) => setState(() => _selectedStudentId = id);

  Future<void> _deleteStudent(int id) async {
    await _database!.deleteStudent(id);
    final profiles = await _database!.profiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _selectedStudentId = profiles.isEmpty ? null : profiles.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final database = _database;
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'ClassWorkPulse could not open its local storage.\n\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profiles.isEmpty) {
      return OnboardingScreen(onSubmit: _saveProfile);
    }
    final profile = _profiles.firstWhere((p) => p.id == _selectedStudentId);
    return HomeScreen(
      database: database,
      profile: profile,
      profiles: _profiles,
      onStudentSelected: _selectStudent,
      onStudentAdded: _addProfile,
      onStudentDeleted: _deleteStudent,
      onProfileChanged: _saveProfile,
    );
  }
}
