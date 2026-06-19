import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

  // Whether to show the notification access page (Android only)
  bool get _showNotificationPage => Platform.isAndroid;

  List<Widget> get _pages => [
        // Page 1: Welcome
        const _OnboardingPage(
          icon: LucideIcons.send,
          title: 'Transfer Anything',
          subtitle:
              'Send files, photos, videos, and folders between\nany device — instantly and privately.',
          color: Color(0xFF6366F1),
        ),
        // Page 2: Notification Access (Android only)
        if (_showNotificationPage)
          _NotificationAccessPage(
            isGranted: _permissionGranted,
            isChecking: _isCheckingPermission,
            onGrant: _requestNotificationAccess,
          ),
        // Page 3: Privacy / Get Started
        const _OnboardingPage(
          icon: LucideIcons.shieldCheck,
          title: 'Privacy First',
          subtitle:
              'No cloud. No account. No tracking.\nAll transfers are encrypted end-to-end.',
          color: Color(0xFF22C55E),
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
    // When user returns from settings, check if permission was granted
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
        // Auto-advance if granted and currently on the notification page
        if (granted && _currentPage == 1) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) _next();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingPermission = false);
    }
  }

  Future<void> _requestNotificationAccess() async {
    try {
      await _notificationChannel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  void _next() {
    final pages = _pages;
    if (_currentPage < pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
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
    final colorScheme = Theme.of(context).colorScheme;
    final pages = _pages;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _complete,
                  child: const Text('Skip'),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, index) => pages[index],
              ),
            ),
            // Dots + Button
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const Gap(32),
                  // Next / Get Started button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(
                        _currentPage == pages.length - 1
                            ? 'Get Started'
                            : 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Static info page ---

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: color),
          ),
          const Gap(40),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const Gap(16),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// --- Notification Access permission page ---

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: isGranted
                ? Container(
                    key: const ValueKey('granted'),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.checkCircle,
                      size: 56,
                      color: Color(0xFF22C55E),
                    ),
                  )
                : Container(
                    key: const ValueKey('request'),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.bellRing,
                      size: 56,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
          ),
          const Gap(40),
          // Title
          Text(
            isGranted ? 'Notification Access Granted' : 'Enable Notification Sync',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const Gap(16),
          // Subtitle
          Text(
            isGranted
                ? 'Your phone notifications will now appear\non your connected devices.'
                : 'Allow Sendate to read your notifications\nso they appear on your connected PC or Mac\n— just like KDE Connect.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          const Gap(32),
          // Action button
          if (!isGranted)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isChecking ? null : onGrant,
                icon: isChecking
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : const Icon(LucideIcons.externalLink, size: 18),
                label: Text(
                  isChecking ? 'Checking...' : 'Grant Notification Access',
                ),
              ),
            ),
          if (!isGranted) ...[
            const Gap(12),
            Text(
              'You\'ll be taken to system settings.\nEnable Sendate and come back here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
