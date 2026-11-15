import 'package:material_ui/material_ui.dart';

import '../models/student_profile.dart';

/// The profile inputs shared by onboarding and the edit-profile dialog:
/// student name, pronouns, teacher name, and how the parent is addressed.
class ProfileFields extends StatefulWidget {
  const ProfileFields({super.key, this.initial, required this.onChanged});

  final StudentProfile? initial;

  /// Called with the current profile, or null while the name is empty.
  final ValueChanged<StudentProfile?> onChanged;

  @override
  State<ProfileFields> createState() => _ProfileFieldsState();
}

class _ProfileFieldsState extends State<ProfileFields> {
  late final _name = TextEditingController(text: widget.initial?.studentName);
  late final _teacher = TextEditingController(
    text: widget.initial?.teacherName,
  );
  late Pronouns _pronouns = widget.initial?.pronouns ?? Pronouns.she;
  late String _parentTitle =
      widget.initial?.parentTitle ?? StudentProfile.defaultParentTitle;

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    super.dispose();
  }

  void _report() {
    final name = _name.text.trim();
    widget.onChanged(
      name.isEmpty
          ? null
          : StudentProfile(
              studentName: name,
              pronouns: _pronouns,
              teacherName: _teacher.text.trim(),
              parentTitle: _parentTitle,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = {...StudentProfile.parentTitles, _parentTitle}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: "Student's name",
            prefixIcon: Icon(Icons.person_outline),
          ),
          onChanged: (_) => _report(),
        ),
        const SizedBox(height: 16),
        Text('Pronouns', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<Pronouns>(
          segments: [
            for (final p in Pronouns.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {_pronouns},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _pronouns = selection.single);
            _report();
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _teacher,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Teacher name (for the sign-off)',
            prefixIcon: Icon(Icons.school_outlined),
          ),
          onChanged: (_) => _report(),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _parentTitle,
          decoration: const InputDecoration(
            labelText: 'Address the parent as',
            prefixIcon: Icon(Icons.family_restroom),
          ),
          items: [
            for (final title in titles)
              DropdownMenuItem(value: title, child: Text(title)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _parentTitle = value);
            _report();
          },
        ),
      ],
    );
  }
}
