import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/constants/app_constants.dart';

final appLockEnabledProvider = StateNotifierProvider<AppLockNotifier, bool>(
  (ref) => AppLockNotifier(),
);

class AppLockNotifier extends StateNotifier<bool> {
  AppLockNotifier() : super(_load());
  static bool _load() => Hive.box(AppConstants.settingsBox).get('app_lock', defaultValue: false) as bool;
  Future<void> toggle() async {
    state = !state;
    await Hive.box(AppConstants.settingsBox).put('app_lock', state);
  }
}

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _auth = LocalAuthentication();
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() { _isAuthenticating = true; _error = null; });

    try {
      final canAuth = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuth) {
        // No biometric available — unlock directly
        widget.onUnlocked();
        return;
      }

      final success = await _auth.authenticate(
        localizedReason: 'Unlock Sendate',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (success) {
        widget.onUnlocked();
      } else {
        setState(() => _error = 'Authentication failed. Tap Unlock to try again.');
      }
    } catch (e) {
      // If auth fails (e.g., no biometric enrolled), allow unlock
      setState(() => _error = e.toString());
      // Auto-unlock after 2s on error so user isn't stuck
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) widget.onUnlocked();
      });
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lock, size: 64, color: colorScheme.primary),
              const Gap(24),
              Text(
                'Sendate is Locked',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Gap(8),
              Text(
                'Authenticate to continue',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              if (_error != null) ...[
                const Gap(16),
                Text(_error!, style: TextStyle(color: colorScheme.error)),
              ],
              const Gap(32),
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _authenticate,
                icon: Icon(LucideIcons.fingerprint),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
