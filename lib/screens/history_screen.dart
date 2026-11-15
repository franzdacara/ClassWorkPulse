import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_database.dart';
import '../models/daily_entry.dart';
import 'daily_log_form.dart';

/// Every saved entry, newest first. Tap one to edit it.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.database,
    required this.studentId,
    required this.studentName,
    required this.onParentUpdate,
  });

  final AppDatabase database;
  final int studentId;
  final String studentName;
  final ValueChanged<DateTime> onParentUpdate;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<DailyEntry>? _entries;

  @override
  void initState() {
    super.initState();
    widget.database.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.database.removeListener(_reload);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) _reload();
  }

  Future<void> _reload() async {
    final entries = await widget.database.entries(widget.studentId);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  void _edit(DailyEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Edit entry')),
          body: DailyLogForm(
            database: widget.database,
            studentId: widget.studentId,
            studentName: widget.studentName,
            initialDate: entry.date,
            allowDateChange: false,
            onSaved: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(DailyEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'The entry for ${DateFormat.yMMMEd().format(entry.date)} will be '
          'removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.database.deleteEntry(entry.date, widget.studentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text('No entries yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                "Entries saved in the Today tab appear here, and are what "
                "the assistant uses to describe ${widget.studentName}'s "
                'progress.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _EntryCard(
          entry: entry,
          onTap: () => _edit(entry),
          onDelete: () => _delete(entry),
          onParentUpdate: () => widget.onParentUpdate(entry.date),
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
    required this.onParentUpdate,
  });

  final DailyEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onParentUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMMMEd().format(entry.date),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: entry.parentUpdate == null
                        ? 'Write parent update'
                        : 'View parent update',
                    icon: Icon(
                      entry.parentUpdate == null
                          ? Icons.forward_to_inbox_outlined
                          : Icons.mark_email_read_outlined,
                    ),
                    onPressed: onParentUpdate,
                  ),
                  IconButton(
                    tooltip: 'Delete entry',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _LevelBadge(
                          label: 'Reading ability',
                          level: entry.readingAbility,
                        ),
                        _LevelBadge(
                          label: 'Comprehension',
                          level: entry.readingComprehension,
                        ),
                      ],
                    ),
                    if (entry.accomplishments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        entry.accomplishments,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (entry.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Notes: ${entry.notes}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.label, required this.level});

  final String label;
  final ReadingLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (level) {
      ReadingLevel.needsSupport => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      ReadingLevel.developing => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ReadingLevel.onTrack => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      ReadingLevel.excelling => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${level.label}',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}
