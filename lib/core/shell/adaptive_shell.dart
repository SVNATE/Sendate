import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../shared/providers/transfer_provider.dart';
import '../../shared/widgets/active_transfers_sheet.dart';

/// Adaptive layout that switches between mobile bottom nav and desktop sidebar.
class AdaptiveShell extends ConsumerWidget {
  final Widget child;
  const AdaptiveShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;

    // Desktop/Tablet: sidebar navigation (> 768px)
    if (width > 768) {
      return _DesktopShell(child: child);
    }

    // Mobile: bottom navigation
    return _MobileShell(child: child);
  }
}

class _MobileShell extends ConsumerWidget {
  final Widget child;
  const _MobileShell({required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/receive')) return 0;
    if (location.startsWith('/send')) return 1;
    if (location.startsWith('/devices')) return 2;
    if (location.startsWith('/history')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/receive');
      case 1: context.go('/send');
      case 2: context.go('/devices');
      case 3: context.go('/history');
      case 4: context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = _currentIndex(context);
    final activeTransfers = ref.watch(activeTransfersProvider);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          child,
          if (activeTransfers.isNotEmpty)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: ActiveTransfersSheet(),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FlushNavBar(
              currentIndex: index,
              onTap: (i) => _onTap(context, i),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlushNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FlushNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
            top: 8,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.65),
            border: Border(
              top: BorderSide(
                color: colorScheme.onSurface.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavBarItem(icon: LucideIcons.download, label: 'Receive', isSelected: currentIndex == 0, onTap: () => onTap(0)),
              _NavBarItem(icon: LucideIcons.send, label: 'Send', isSelected: currentIndex == 1, onTap: () => onTap(1)),
              _NavBarItem(icon: LucideIcons.monitorSmartphone, label: 'Devices', isSelected: currentIndex == 2, onTap: () => onTap(2)),
              _NavBarItem(icon: LucideIcons.clock, label: 'History', isSelected: currentIndex == 3, onTap: () => onTap(3)),
              _NavBarItem(icon: LucideIcons.settings, label: 'Settings', isSelected: currentIndex == 4, onTap: () => onTap(4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({required this.icon, required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: 4,
              width: isSelected ? 20 : 0,
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopShell extends ConsumerWidget {
  final Widget child;
  const _DesktopShell({required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/receive')) return 0;
    if (location.startsWith('/send')) return 1;
    if (location.startsWith('/devices')) return 2;
    if (location.startsWith('/history')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/receive');
      case 1: context.go('/send');
      case 2: context.go('/devices');
      case 3: context.go('/history');
      case 4: context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = _currentIndex(context);
    final colorScheme = Theme.of(context).colorScheme;
    final activeTransfers = ref.watch(activeTransfersProvider);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _onTap(context, i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Icon(LucideIcons.send, color: colorScheme.primary, size: 28),
                  const SizedBox(height: 4),
                  Text('Sendate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colorScheme.primary)),
                ],
              ),
            ),
            destinations: [
              NavigationRailDestination(icon: Icon(LucideIcons.download), label: const Text('Receive')),
              NavigationRailDestination(icon: Icon(LucideIcons.send), label: const Text('Send')),
              NavigationRailDestination(icon: Icon(LucideIcons.monitorSmartphone), label: const Text('Devices')),
              NavigationRailDestination(icon: Icon(LucideIcons.clock), label: const Text('History')),
              NavigationRailDestination(icon: Icon(LucideIcons.settings), label: const Text('Settings')),
            ],
          ),
          VerticalDivider(width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          // Main content
          Expanded(
            child: Stack(
              children: [
                child,
                if (activeTransfers.isNotEmpty)
                  const Positioned(left: 16, right: 16, bottom: 0, child: ActiveTransfersSheet()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
