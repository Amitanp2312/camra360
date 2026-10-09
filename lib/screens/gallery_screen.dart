import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/core/providers.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/models/session.dart';
import 'package:sphere360/screens/live_capture_screen.dart';
import 'package:sphere360/screens/settings_screen.dart';
import 'package:sphere360/screens/viewer_screen.dart';
import 'package:sphere360/services/auth_service.dart';
import 'package:sphere360/services/supabase_service.dart';
import 'package:sphere360/widgets/session_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GalleryEntry {
  const GalleryEntry({
    required this.session,
    required this.captureCount,
    this.thumbnailUrl,
  });

  final CaptureSession session;
  final int captureCount;
  final String? thumbnailUrl;
}

class GalleryNotifier extends AsyncNotifier<List<GalleryEntry>> {
  @override
  Future<List<GalleryEntry>> build() => _load();

  Future<void> refresh() async {
    try {
      state = AsyncData(await _load());
    } catch (error, stackTrace) {
      if (state.hasValue) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      state = AsyncError(error, stackTrace);
    }
  }

  void remove(String sessionId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final entry in current)
        if (entry.session.id != sessionId) entry,
    ]);
  }

  void rename(String sessionId, String title) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final entry in current)
        if (entry.session.id == sessionId)
          GalleryEntry(
            session: entry.session.withTitle(title),
            captureCount: entry.captureCount,
            thumbnailUrl: entry.thumbnailUrl,
          )
        else
          entry,
    ]);
  }

  Future<List<GalleryEntry>> _load() {
    return _fetchGallery().timeout(AppConstants.networkTimeout);
  }

  Future<List<GalleryEntry>> _fetchGallery() async {
    final service = ref.read(supabaseServiceProvider);
    final sessions = await service.fetchSessions();
    final counts = await service.fetchCaptureCounts([
      for (final session in sessions) session.id,
    ]);
    final paths = [for (final session in sessions) ?_thumbnailPath(session)];
    final signed = await service.createSignedUrls(paths);
    final urls = <String, String>{};
    for (final result in signed) {
      if (result is SignedUrlSuccess) {
        urls[result.path] = result.signedUrl;
      }
    }
    return [
      for (final session in sessions)
        GalleryEntry(
          session: session,
          captureCount: counts[session.id] ?? 0,
          thumbnailUrl: urls[_thumbnailPath(session) ?? ''],
        ),
    ];
  }
}

String? _thumbnailPath(CaptureSession session) {
  final thumb = session.thumbPath;
  if (thumb != null && thumb.isNotEmpty) return thumb;
  final preview = session.previewPath;
  if (preview != null && preview.isNotEmpty) return preview;
  return null;
}

final galleryProvider =
    AsyncNotifierProvider<GalleryNotifier, List<GalleryEntry>>(
      GalleryNotifier.new,
    );

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  bool _signingOut = false;
  var _resumePrompted = false;
  final _selected = <String>{};

  Future<void> _refresh() async {
    try {
      await ref.read(galleryProvider.notifier).refresh();
    } on SupabaseServiceException catch (error) {
      _showMessage(error.message);
    } on TimeoutException {
      _showMessage(
        'Loading sessions took too long. Check the connection and try again.',
      );
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
    } on AuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(GalleryEntry entry) async {
    final saved = await showSessionNameDialog(
      context,
      initialName: entry.session.title ?? '',
    );
    if (saved == null || !mounted) return;
    try {
      await ref
          .read(supabaseServiceProvider)
          .updateSession(entry.session.id, title: saved);
      ref.read(galleryProvider.notifier).rename(entry.session.id, saved);
    } on SupabaseServiceException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _deleteFromMenu(GalleryEntry entry) async {
    final removed = await _delete(entry);
    if (!removed || !mounted) return;
    ref.read(galleryProvider.notifier).remove(entry.session.id);
  }

  Future<bool> _delete(GalleryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: const Text('Delete session?'),
          content: const Text(
            'This removes the session, its captures, and the stored images.',
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
        );
      },
    );
    if (confirmed != true || !mounted) return false;

    try {
      await ref.read(supabaseServiceProvider).deleteSession(entry.session.id);
      return true;
    } on SupabaseServiceException catch (error) {
      _showMessage(error.message);
      return false;
    } catch (error) {
      _showMessage('$error');
      return false;
    }
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: Text(ids.length == 1 ? 'Delete session?' : 'Delete ${ids.length} sessions?'),
          content: const Text(
            'This removes the sessions, their captures, and the stored images.',
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
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final failures = <String>[];
    for (final id in ids) {
      try {
        await ref.read(supabaseServiceProvider).deleteSession(id);
        if (!mounted) return;
        ref.read(galleryProvider.notifier).remove(id);
        setState(() => _selected.remove(id));
      } on SupabaseServiceException catch (error) {
        failures.add(error.message);
      } catch (error) {
        failures.add('$error');
      }
    }
    if (!mounted) return;
    if (failures.isNotEmpty) {
      _showMessage(
        failures.length == 1
            ? failures.first
            : 'Could not delete ${failures.length} sessions. ${failures.first}',
      );
    }
  }

  Future<void> _openLive({String? sessionId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LiveCaptureScreen(sessionId: sessionId),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _promptUnfinished(CaptureSession session) async {
    final choice = await showDialog<_UnfinishedChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: const Text('Unfinished capture'),
          content: const Text(
            'This capture was still in progress when Sphere360 closed. '
            'Resume it, or discard the session and its photos.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnfinishedChoice.discard),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_UnfinishedChoice.resume),
              child: const Text('Resume'),
            ),
          ],
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == _UnfinishedChoice.discard) {
      try {
        await ref.read(supabaseServiceProvider).deleteSession(session.id);
        if (!mounted) return;
        ref.read(galleryProvider.notifier).remove(session.id);
      } on SupabaseServiceException catch (error) {
        _showMessage(error.message);
      } catch (error) {
        _showMessage('$error');
      }
      return;
    }
    await _openLive(sessionId: session.id);
  }

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider);
    ref.listen(galleryProvider, (_, next) {
      if (_resumePrompted) return;
      final entries = next.asData?.value;
      if (entries == null) return;
      CaptureSession? open;
      for (final entry in entries) {
        if (entry.session.status == SessionStatus.capturing) {
          open = entry.session;
          break;
        }
      }
      if (open == null) return;
      _resumePrompted = true;
      final session = open;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_promptUnfinished(session));
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? AppConstants.appName
              : '${_selected.length} selected',
        ),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => setState(() => _selected.clear()),
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Delete selected',
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Live capture',
        onPressed: () => _openLive(),
        child: const Icon(Icons.camera_alt),
      ),
      body: gallery.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StatusList(
          onRefresh: _refresh,
          child: _MessageState(
            message: error is TimeoutException
                ? 'Loading sessions took too long. Check the connection and try again.'
                : '$error',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(galleryProvider),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return _StatusList(
              onRefresh: _refresh,
              child: const _MessageState(
                message:
                    'No sessions yet.\nTap the camera button to start one.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final title = entry.session.title;
                final selecting = _selected.isNotEmpty;
                final card = SessionCard(
                  title: (title == null || title.isEmpty) ? 'Untitled' : title,
                  startedAt: entry.session.startedAt,
                  captureCount: entry.captureCount,
                  status: entry.session.status,
                  thumbnailUrl: entry.thumbnailUrl,
                  selecting: selecting,
                  selected: _selected.contains(entry.session.id),
                  onRename: () => _rename(entry),
                  onDelete: () => _deleteFromMenu(entry),
                  onLongPress: () => _toggleSelected(entry.session.id),
                  onTap: () {
                    if (selecting) {
                      _toggleSelected(entry.session.id);
                      return;
                    }
                    if (entry.session.status == SessionStatus.capturing) {
                      unawaited(_openLive(sessionId: entry.session.id));
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            ViewerScreen(sessionId: entry.session.id),
                      ),
                    );
                  },
                );
                if (selecting) return card;
                return Dismissible(
                  key: ValueKey(entry.session.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _delete(entry),
                  onDismissed: (_) {
                    ref.read(galleryProvider.notifier).remove(entry.session.id);
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: SphereColors.danger,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  child: card,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

enum _UnfinishedChoice { resume, discard }

class _StatusList extends StatelessWidget {
  const _StatusList({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.panorama_horizontal,
              color: SphereColors.accent,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SphereColors.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
