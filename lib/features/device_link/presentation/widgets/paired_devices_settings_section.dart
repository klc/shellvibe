import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/device_link_pairing_repository.dart';
import '../../data/repositories/device_link_pairing_storage.dart';
import '../../domain/models/device_link_pairing_profile.dart';

/// Settings surface for both sides of the pairing contract:
/// desktop authorization rows in Drift and mobile profiles in secure storage.
final class PairedDevicesSettingsSection extends ConsumerStatefulWidget {
  const PairedDevicesSettingsSection({super.key});

  @override
  ConsumerState<PairedDevicesSettingsSection> createState() =>
      _PairedDevicesSettingsSectionState();
}

class _PairedDevicesSettingsSectionState
    extends ConsumerState<PairedDevicesSettingsSection> {
  late Future<List<DeviceLinkPairingProfile>> _mobileProfiles;

  @override
  void initState() {
    super.initState();
    _mobileProfiles = _loadMobileProfiles();
  }

  Future<List<DeviceLinkPairingProfile>> _loadMobileProfiles() {
    return DeviceLinkPairingStorage(
      ref.read(secureStorageServiceProvider),
    ).getAll();
  }

  Future<void> _removeMobileProfile(String id) async {
    await DeviceLinkPairingStorage(
      ref.read(secureStorageServiceProvider),
    ).remove(id);
    if (!mounted) return;
    setState(() => _mobileProfiles = _loadMobileProfiles());
  }

  Future<void> _removeDesktopDevice(String id) async {
    await ref.read(deviceLinkPairingRepositoryProvider).remove(id);
    if (mounted) ref.invalidate(pairedDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktopDevices = ref.watch(pairedDevicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIntro(theme),
        const SizedBox(height: 12),
        desktopDevices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load paired devices: $error'),
          data: (devices) => _buildDesktopDevices(context, devices),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<DeviceLinkPairingProfile>>(
          future: _mobileProfiles,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            return _buildMobileProfiles(context, snapshot.data ?? const []);
          },
        ),
      ],
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return Text(
      'QR pairing is used only once. Remove a device to reject future '
      'reconnects with its stored secret.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildDesktopDevices(
    BuildContext context,
    List<PairedDevice> devices,
  ) {
    return ShadCard(
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Authorized devices'),
          ),
          const Divider(),
          if (devices.isEmpty)
            const ListTile(
              leading: Icon(LucideIcons.monitorSmartphone),
              title: Text('No devices have been paired on this desktop.'),
            )
          else
            for (final device in devices)
              ListTile(
                key: Key('paired_device_${device.id}'),
                leading: Icon(_platformIcon(device.platform)),
                title: Text(device.name),
                subtitle: Text(
                  '${device.platform} · last seen ${_formatDate(device.lastSeenAt)}',
                ),
                trailing: IconButton(
                  key: Key('remove_paired_device_${device.id}'),
                  tooltip: 'Remove device',
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _removeDesktopDevice(device.id),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildMobileProfiles(
    BuildContext context,
    List<DeviceLinkPairingProfile> profiles,
  ) {
    return ShadCard(
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Saved desktops'),
          ),
          const Divider(),
          if (profiles.isEmpty)
            const ListTile(
              leading: Icon(LucideIcons.smartphone),
              title: Text('No saved Device Link desktops.'),
            )
          else
            for (final profile in profiles)
              ListTile(
                key: Key('saved_device_link_${profile.id}'),
                leading: Icon(_platformIcon(profile.platform)),
                title: Text(profile.name),
                subtitle: Text(
                  '${profile.host}:${profile.port} · paired ${_formatDate(profile.pairedAt)}',
                ),
                trailing: IconButton(
                  key: Key('remove_saved_device_link_${profile.id}'),
                  tooltip: 'Remove pairing',
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _removeMobileProfile(profile.id),
                ),
              ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'ios' || 'android' => LucideIcons.smartphone,
      _ => LucideIcons.monitor,
    };
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
