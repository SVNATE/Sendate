import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
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
      setState(() => _error = 'Cannot use biometrics right now.');
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
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.lock, size: 64, color: colorScheme.primary),
              ),
              const Gap(40),
              Text(
                'Locked',
                style: GoogleFonts.outfit(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  color: colorScheme.onSurface,
                ),
              ),
              const Gap(12),
              Text(
                'Authenticate to access Sendate',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const Gap(24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.plusJakartaSans(color: colorScheme.error, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const Gap(48),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isAuthenticating ? null : _authenticate,
                  icon: _isAuthenticating
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                      : const Icon(LucideIcons.fingerprint, size: 24),
                  label: Text(_isAuthenticating ? 'Authenticating...' : 'Unlock', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
