import 'package:material_ui/material_ui.dart';

import '../ai/assistant_controller.dart';
import '../data/app_database.dart';
import '../models/student_profile.dart';
import 'assistant_screen.dart';
import 'daily_log_form.dart';
import 'history_screen.dart';
import 'parent_update_screen.dart';
import 'dashboard_screen.dart';

/// Main shell: the daily log, the saved history and the assistant.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.database,
    required this.profile,
    required this.profiles,
    required this.onStudentSelected,
    required this.onStudentAdded,
    required this.onStudentDeleted,
    required this.onProfileChanged,
    required this.onOpenDashboard,
  });

  final AppDatabase database;
  final StudentProfile profile;
  final List<StudentProfile> profiles;
  final ValueChanged<int> onStudentSelected;
  final Future<void> Function(StudentProfile profile) onStudentAdded;
  final Future<void> Function(int studentId) onStudentDeleted;
  final Future<void> Function(StudentProfile profile) onProfileChanged;
  final VoidCallback onOpenDashboard;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _assistantTab = 2;

  late final AssistantController _assistant = AssistantController(
    widget.database,
    widget.profile.id!,
  );
  int _tab = 0;

  /// The model is only loaded once the assistant is first opened.
  bool _assistantOpened = false;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _assistant.switchStudent(widget.profile.id!);
      if (_tab == _assistantTab) _assistant.start();
    }
  }

  @override
  void dispose() {
    _assistant.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final firstAssistantVisit = index == _assistantTab && !_assistantOpened;
    setState(() {
      _tab = index;
      if (firstAssistantVisit) _assistantOpened = true;
    });
    if (firstAssistantVisit) _assistant.start();
  }

  void _openParentUpdate(DateTime date) => openParentUpdate(
    context,
    assistant: _assistant,
    database: widget.database,
    studentId: widget.profile.id!,
    profile: widget.profile,
    date: date,
  );

  Future<void> _editProfile() async {
    final profile = await showDialog<StudentProfile>(
      context: context,
      builder: (context) => StudentProfileDialog(
        initial: widget.profile,
        title: 'Student and teacher',
      ),
    );
    if (profile != null) await widget.onProfileChanged(profile);
  }

  Future<void> _addStudent() async {
    final profile = await showDialog<StudentProfile>(
      context: context,
      builder: (context) => const StudentProfileDialog(title: 'Add student'),
    );
    if (profile != null) await widget.onStudentAdded(profile);
  }

  Future<void> _deleteStudent() async {
    if (widget.profiles.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one student profile.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.profile.studentName}?'),
        content: const Text(
          'This removes the student and all of their saved entries from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onStudentDeleted(widget.profile.id!);
    }
  }

  Future<void> _manageStudents() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('Students'),
              subtitle: Text('Choose who you are tracking'),
            ),
            for (final profile in widget.profiles)
              ListTile(
                leading: Icon(
                  profile.id == widget.profile.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(profile.studentName),
                onTap: () {
                  Navigator.pop(context);
                  if (profile.id != widget.profile.id) {
                    widget.onStudentSelected(profile.id!);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Add student'),
              onTap: () {
                Navigator.pop(context);
                _addStudent();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile.studentName;
    final title = switch (_tab) {
      0 => "$name's daily log",
      1 => 'History',
      _ => 'Assistant',
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Student dashboard',
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onOpenDashboard,
        ),
        title: Text(title),
        actions: [
          if (_tab == _assistantTab)
            ListenableBuilder(
              listenable: _assistant,
              builder: (context, _) => IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: _assistant.messages.isEmpty || _assistant.isBusy
                    ? null
                    : _assistant.newChat,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Student profiles',
            icon: const Icon(Icons.people_outline),
            onSelected: (action) {
              switch (action) {
                case 'manage':
                  _manageStudents();
                case 'edit':
                  _editProfile();
                case 'delete':
                  _deleteStudent();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'manage',
                child: Text('Switch student (${widget.profile.studentName})'),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit student and teacher'),
              ),
              if (widget.profiles.length > 1)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete this student'),
                ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DailyLogForm(
            database: widget.database,
            studentId: widget.profile.id!,
            studentName: name,
            initialDate: DateTime.now(),
            onParentUpdate: _openParentUpdate,
          ),
          HistoryScreen(
            database: widget.database,
            studentId: widget.profile.id!,
            studentName: name,
            onParentUpdate: _openParentUpdate,
          ),
          if (_assistantOpened)
            AssistantScreen(
              controller: _assistant,
              database: widget.database,
              profile: widget.profile,
              studentId: widget.profile.id!,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Today',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant',
          ),
        ],
      ),
    );
  }
}
