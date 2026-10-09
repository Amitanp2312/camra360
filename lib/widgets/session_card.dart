import 'package:flutter/material.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/models/session.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.title,
    required this.startedAt,
    required this.captureCount,
    required this.status,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.thumbnailUrl,
  });

  final String title;
  final DateTime? startedAt;
  final int captureCount;
  final SessionStatus status;
  final String? thumbnailUrl;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capturing = status == SessionStatus.capturing;
    final statusColor = capturing ? SphereColors.accent : SphereColors.captured;
    final countLabel = captureCount == 1
        ? '1 capture'
        : '$captureCount captures';

    return Material(
      color: SphereColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (selecting) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? SphereColors.accent : SphereColors.muted,
                ),
                const SizedBox(width: 8),
              ],
              _Thumbnail(url: thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatSessionDate(startedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SphereColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(countLabel, style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            capturing ? 'Capturing' : 'Complete',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SessionMenuButton(onRename: onRename, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionMenuButton extends StatelessWidget {
  const SessionMenuButton({
    super.key,
    required this.onRename,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SessionMenuAction>(
      tooltip: 'Session options',
      onSelected: (action) {
        switch (action) {
          case _SessionMenuAction.rename:
            onRename();
          case _SessionMenuAction.delete:
            onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _SessionMenuAction.rename,
          child: Text('Edit name'),
        ),
        PopupMenuItem(
          value: _SessionMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
  }
}

enum _SessionMenuAction { rename, delete }

/// Asks for a session name. Returns null when the dialog is cancelled.
Future<String?> showSessionNameDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(initialName: initialName),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initialName});

  final String initialName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SphereColors.surface,
      title: const Text('Edit name'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: 'Name',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 64,
        child: url == null
            ? const ColoredBox(
                color: SphereColors.surfaceHigh,
                child: Icon(
                  Icons.panorama_horizontal,
                  color: SphereColors.muted,
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: SphereColors.surfaceHigh,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: SphereColors.muted,
                    ),
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(
                    color: SphereColors.surfaceHigh,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatSessionDate(DateTime? value) {
  if (value == null) return 'No date';
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hour:$minute';
}
