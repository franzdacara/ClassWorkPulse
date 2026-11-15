import 'package:material_ui/material_ui.dart';

import '../models/student_profile.dart';
import 'profile_fields.dart';

/// Landing screen that lists every student before opening their workspace.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.profiles,
    required this.onStudentSelected,
    required this.onStudentAdded,
    required this.onStudentDeleted,
  });

  final List<StudentProfile> profiles;
  final ValueChanged<int> onStudentSelected;
  final Future<void> Function(StudentProfile profile) onStudentAdded;
  final Future<void> Function(int studentId) onStudentDeleted;

  Future<void> _addStudent(BuildContext context) async {
    final profile = await showDialog<StudentProfile>(
      context: context,
      builder: (context) => const StudentProfileDialog(title: 'Add student'),
    );
    if (profile != null) await onStudentAdded(profile);
  }

  Future<void> _deleteStudent(
    BuildContext context,
    StudentProfile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${profile.studentName}?'),
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
    if (confirmed == true) await onStudentDeleted(profile.id!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Student dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Your students', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Choose a student to view their daily progress.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final profile in profiles)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    profile.studentName.substring(0, 1).toUpperCase(),
                  ),
                ),
                title: Text(profile.studentName),
                subtitle: const Text('Open progress workspace'),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'delete') {
                      _deleteStudent(context, profile);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete student'),
                    ),
                  ],
                ),
                onTap: () => onStudentSelected(profile.id!),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _addStudent(context),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add student'),
          ),
        ],
      ),
    );
  }
}

class StudentProfileDialog extends StatefulWidget {
  const StudentProfileDialog({super.key, this.initial, required this.title});

  final StudentProfile? initial;
  final String title;

  @override
  State<StudentProfileDialog> createState() => _StudentProfileDialogState();
}

class _StudentProfileDialogState extends State<StudentProfileDialog> {
  late StudentProfile? _profile = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: ProfileFields(
          initial: widget.initial,
          onChanged: (profile) => setState(() => _profile = profile),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _profile == null
              ? null
              : () => Navigator.of(context).pop(_profile),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
