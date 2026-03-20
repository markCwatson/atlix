import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/features/profiles/models/rifle_profile.dart';
import 'package:monyx/features/profiles/providers/profile_provider.dart';
import 'rifle_profile_form.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(rifleProfilesProvider);
    final activeProfile = ref.watch(activeRifleProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rifle Profiles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New profile',
            onPressed: () => _openForm(context, ref, null),
          ),
        ],
      ),
      body: profiles.isEmpty
          ? const Center(child: Text('No profiles – tap + to add one'))
          : ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (context, i) {
                final profile = profiles[i];
                final isActive = activeProfile?.id == profile.id;
                return _ProfileTile(
                  profile: profile,
                  isActive: isActive,
                  onSetActive: () {
                    ref.read(activeRifleProfileProvider.notifier).state = profile;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Active: ${profile.name}')),
                    );
                  },
                  onEdit: () => _openForm(context, ref, profile),
                  onDelete: profiles.length > 1
                      ? () => ref
                            .read(rifleProfilesProvider.notifier)
                            .deleteProfile(profile.id)
                      : null,
                );
              },
            ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref, RifleProfile? existing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RifleProfileForm(existing: existing),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onSetActive,
    required this.onEdit,
    this.onDelete,
  });

  final RifleProfile profile;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? const BorderSide(color: AppTheme.primaryOrange, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              isActive ? AppTheme.primaryOrange : AppTheme.surfaceCard,
          child: Icon(
            Icons.adjust,
            color: isActive ? Colors.black : AppTheme.textSecondary,
          ),
        ),
        title: Text(
          profile.name,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${profile.caliber}  •  '
          '${profile.bulletProfile.bulletWeightGrains.toStringAsFixed(0)}gr  •  '
          '${profile.bulletProfile.muzzleVelocityFps.toStringAsFixed(0)} fps  •  '
          'Zero ${profile.zeroDistanceYards.toStringAsFixed(0)} yds',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'activate', child: Text('Set Active')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (onDelete != null)
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppTheme.errorRed)),
              ),
          ],
          onSelected: (val) {
            switch (val) {
              case 'activate':
                onSetActive();
              case 'edit':
                onEdit();
              case 'delete':
                onDelete?.call();
            }
          },
        ),
        onTap: onSetActive,
      ),
    );
  }
}
