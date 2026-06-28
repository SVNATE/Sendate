import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import '../../../../core/constants/app_constants.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _controller = PageController();
  int _currentPage = 0;
  bool _permissionGranted = false;
  bool _isCheckingPermission = false;

  static const _notificationChannel =
      MethodChannel('com.svnate.sendate/notification_listener');

  bool get _showNotificationPage => Platform.isAndroid;

  List<Widget> get _pages => [
        const _OnboardingPage(
          titleLine1: 'Transfer',
          titleLine2: 'Anything.',
          subtitle:
              'Send files, photos, videos, and folders between any device. Instantly.',
        ),
        const _OnboardingPage(
          titleLine1: 'Lightning',
          titleLine2: 'Fast.',
          subtitle:
              'No internet? No problem. Transfer massive files seamlessly over local Wi-Fi.',
        ),
        if (_showNotificationPage)
          _NotificationAccessPage(
            isGranted: _permissionGranted,
            isChecking: _isCheckingPermission,
            onGrant: _requestNotificationAccess,
          ),
        const _OnboardingPage(
          titleLine1: 'Total',
          titleLine2: 'Privacy.',
          subtitle:
              'No cloud. No account. No tracking. All transfers are encrypted end-to-end.',
        ),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_showNotificationPage) {
      _checkPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _showNotificationPage) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    setState(() => _isCheckingPermission = true);
    try {
      final result =
          await _notificationChannel.invokeMethod<bool>('isPermissionGranted');
      final granted = result ?? false;
      if (mounted) {
        setState(() {
          _permissionGranted = granted;
          _isCheckingPermission = false;
        });
        if (granted && _currentPage == 1) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) _next();
        }
      }
    } catch (e) {
      debugPrint('[Onboarding] Permission check failed: $e');
      if (mounted) setState(() => _isCheckingPermission = false);
    }
  }

  Future<void> _requestNotificationAccess() async {
    try {
      await _notificationChannel.invokeMethod('openPermissionSettings');
    } catch (e) {
      debugPrint('[Onboarding] Open permission settings failed: $e');
    }
  }

  void _next() {
    final pages = _pages;
    if (_currentPage < pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.fastOutSlowIn,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    Hive.box(AppConstants.settingsBox).put('onboarding_complete', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => pages[index],
          ),
          
          // Skip button
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _complete,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 800.ms),
              ),
            ),
          ),
          
          // Bottom Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modern line indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutExpo,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 48 : 12,
                        height: 3,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 600.ms),
                  const Gap(48),
                  // Next / Get Started button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _next,
                      child: Text(
                        _currentPage == pages.length - 1
                            ? 'Get Started'
                            : 'Continue',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final String titleLine1;
  final String titleLine2;
  final String subtitle;

  const _OnboardingPage({
    required this.titleLine1,
    required this.titleLine2,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Gap(80),
            Text(
              titleLine1,
              style: GoogleFonts.outfit(
                fontSize: 64,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                height: 1.0,
                letterSpacing: -2,
              ),
            ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutCubic),
            Text(
              titleLine2,
              style: GoogleFonts.outfit(
                fontSize: 64,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                height: 1.0,
                letterSpacing: -2,
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutCubic),
            const Gap(32),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ).animate().fadeIn(delay: 200.ms).scaleX(alignment: Alignment.centerLeft),
            const Gap(32),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
          ],
        ),
      ),
    );
  }
}

class _NotificationAccessPage extends StatelessWidget {
  final bool isGranted;
  final bool isChecking;
  final VoidCallback onGrant;

  const _NotificationAccessPage({
    required this.isGranted,
    required this.isChecking,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Gap(80),
            Text(
              isGranted ? 'Sync' : 'Enable',
              style: GoogleFonts.outfit(
                fontSize: 64,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                height: 1.0,
                letterSpacing: -2,
              ),
            ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutCubic),
            Text(
              'Sync.',
              style: GoogleFonts.outfit(
                fontSize: 64,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                height: 1.0,
                letterSpacing: -2,
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutCubic),
            const Gap(32),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ).animate().fadeIn(delay: 200.ms).scaleX(alignment: Alignment.centerLeft),
            const Gap(32),
            Text(
              isGranted
                  ? 'Your notifications will sync securely.'
                  : 'Allow Sendate to read notifications so they appear on your connected devices.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const Gap(48),
            if (!isGranted)
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isChecking ? null : onGrant,
                  child: isChecking
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : Text(
                          'Grant Access',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
          ],
        ),
      ),
    );
  }
}
