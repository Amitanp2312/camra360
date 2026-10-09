import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/core/providers.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/services/auth_service.dart';
import 'package:sphere360/services/supabase_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final uploads = ref.watch(pendingUploadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Panorama width', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: AppConstants.previewWidthStandard,
                label: Text('1600'),
              ),
              ButtonSegment(
                value: AppConstants.previewWidthHigh,
                label: Text('2400'),
              ),
            ],
            selected: {settings.previewWidth},
            onSelectionChanged: (next) {
              ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(previewWidth: next.first));
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Width of the equirectangular JPEG. 2400 is sharper and slower to build.',
            style: TextStyle(color: SphereColors.muted),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Upload on Wi-Fi only'),
            subtitle: const Text(
              'Photos stay on the phone until Wi-Fi is available.',
            ),
            value: settings.wifiOnly,
            onChanged: (value) async {
              await ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(wifiOnly: value));
              ref.read(uploadQueueProvider).resumeNow();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save location'),
            subtitle: const Text(
              'Off until you turn it on. The next capture then asks for permission.',
            ),
            value: settings.saveLocation,
            onChanged: (value) {
              ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(saveLocation: value));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compare seams'),
            subtitle: const Text(
              'The viewer can show the panorama before and after exposure matching and edge feathering.',
            ),
            value: settings.seamDebug,
            onChanged: (value) {
              ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(seamDebug: value));
            },
          ),
          const SizedBox(height: 8),
          Text('Uploads', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          uploads.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('$error'),
            data: (jobs) {
              if (jobs.isEmpty) {
                return const Text(
                  'No photos waiting to upload.',
                  style: TextStyle(color: SphereColors.muted),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final job in jobs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        job.lastError == null
                            ? 'Waiting · ${job.attempts} ${job.attempts == 1 ? 'try' : 'tries'}'
                            : job.lastError!,
                        style: const TextStyle(color: SphereColors.muted),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: () =>
                          ref.read(uploadQueueProvider).resumeNow(),
                      child: const Text('Retry uploads'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _signOut(context, ref),
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _deleteData(context, ref),
            child: const Text(
              'Delete my panoramas',
              style: TextStyle(color: SphereColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) Navigator.of(context).pop();
    } on AuthFailure catch (error) {
      if (!context.mounted) return;
      _message(context, error.message);
    }
  }

  Future<void> _deleteData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: const Text('Delete your panoramas?'),
          content: const Text(
            'This removes your sessions, hotspots, and stored photos, '
            'and the photos still waiting to upload on this phone. '
            'Your login stays, and you will be signed out.',
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
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(supabaseServiceProvider).deleteOwnedData();
      await ref.read(uploadQueueProvider).clearLocal();
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) Navigator.of(context).pop();
    } on SupabaseServiceException catch (error) {
      if (!context.mounted) return;
      _message(context, error.message);
    } on AuthFailure catch (error) {
      if (!context.mounted) return;
      _message(context, error.message);
    } catch (error) {
      if (!context.mounted) return;
      _message(context, '$error');
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
