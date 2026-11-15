import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_database.dart';
import '../models/daily_entry.dart';

/// Form for recording one day: accomplishments, reading ability, reading
/// comprehension and free notes. There is one entry per day, so opening a day
/// that already has an entry edits it.
class DailyLogForm extends StatefulWidget {
  const DailyLogForm({
    super.key,
    required this.database,
    required this.studentId,
    required this.studentName,
    required this.initialDate,
    this.allowDateChange = true,
    this.onSaved,
    this.onParentUpdate,
  });

  final AppDatabase database;
  final int studentId;
  final String studentName;
  final DateTime initialDate;

  /// Whether the day being logged can be changed from within the form.
  final bool allowDateChange;
  final VoidCallback? onSaved;

  /// Opens the parent update for a saved day. No button is shown when null.
  final ValueChanged<DateTime>? onParentUpdate;

  @override
  State<DailyLogForm> createState() => _DailyLogFormState();
}

class _DailyLogFormState extends State<DailyLogForm> {
  final _accomplishments = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date = dateOnly(widget.initialDate);
  ReadingLevel? _ability;
  ReadingLevel? _comprehension;

  /// Whether the selected day already has a saved entry.
  bool _existing = false;
  bool _dirty = false;
  bool _saving = false;
  bool _showMissing = false;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    widget.database.addListener(_onDatabaseChanged);
    _load();
  }

  @override
  void dispose() {
    widget.database.removeListener(_onDatabaseChanged);
    _accomplishments.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DailyLogForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) {
      _dirty = false;
      _load();
    }
  }

  /// Picks up edits and deletions made elsewhere, unless that would overwrite
  /// what is being typed here.
  void _onDatabaseChanged() {
    if (!_dirty && !_saving) _load();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final entry = await widget.database.entryFor(_date, widget.studentId);
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _existing = entry != null;
      _accomplishments.text = entry?.accomplishments ?? '';
      _notes.text = entry?.notes ?? '';
      _ability = entry?.readingAbility;
      _comprehension = entry?.readingComprehension;
      _dirty = false;
      _showMissing = false;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      helpText: 'Entry date',
    );
    if (picked == null || !mounted || dateOnly(picked) == _date) return;

    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'This entry has changes that have not been saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }

    setState(() {
      _date = dateOnly(picked);
      _dirty = false;
    });
    await _load();
  }

  Future<void> _save() async {
    final ability = _ability;
    final comprehension = _comprehension;
    if (ability == null || comprehension == null) {
      setState(() => _showMissing = true);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await widget.database.saveEntry(
        DailyEntry(
          date: _date,
          accomplishments: _accomplishments.text.trim(),
          readingAbility: ability,
          readingComprehension: comprehension,
          notes: _notes.text.trim(),
        ),
        widget.studentId,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save the entry: $error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
      _existing = true;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Entry saved for ${DateFormat.yMMMd().format(_date)}'),
      ),
    );
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.studentName;
    final isToday = _date == dateOnly(DateTime.now());
    final dateLabel = DateFormat.yMMMEd().format(_date);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isToday ? 'Today, $dateLabel' : dateLabel,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (widget.allowDateChange)
              TextButton(onPressed: _pickDate, child: const Text('Change')),
          ],
        ),
        if (_existing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This day already has an entry. Saving will update it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('What did $name accomplish?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _accomplishments,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Read two chapters aloud and retold the story',
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 24),
        _LevelPicker(
          title: 'Reading ability',
          description: 'How accurately and fluently $name read.',
          value: _ability,
          showMissing: _showMissing,
          onChanged: (level) => setState(() {
            _ability = level;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 24),
        _LevelPicker(
          title: 'Reading comprehension',
          description: 'How well $name understood what was read.',
          value: _comprehension,
          showMissing: _showMissing,
          onChanged: (level) => setState(() {
            _comprehension = level;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 24),
        Text('Additional notes', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Anything else worth remembering (optional)',
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_existing ? 'Update entry' : 'Save entry'),
        ),
        if (widget.onParentUpdate != null && _existing && !_dirty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => widget.onParentUpdate!(_date),
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: const Text('Write parent update'),
          ),
        ],
      ],
    );
  }
}

class _LevelPicker extends StatelessWidget {
  const _LevelPicker({
    required this.title,
    required this.description,
    required this.value,
    required this.showMissing,
    required this.onChanged,
  });

  final String title;
  final String description;
  final ReadingLevel? value;

  /// Whether to flag that nothing has been chosen yet.
  final bool showMissing;
  final ValueChanged<ReadingLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final level in ReadingLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: value == level,
                onSelected: (_) => onChanged(level),
              ),
          ],
        ),
        if (showMissing && value == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Choose a rating to save the entry.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
