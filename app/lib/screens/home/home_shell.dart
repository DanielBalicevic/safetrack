import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'alerts_tab.dart';
import 'geofence_tab.dart';
import 'history_tab.dart';
import 'map_tab.dart';
import 'profile_tab.dart';

/// Main layout with the bottom navigation. An [IndexedStack] keeps each tab's
/// state when switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Tabs are built on first visit so three native maps are not created at startup.
  final Set<int> _visited = {0};

  static const _destinations = <_Destination>[
    _Destination('Home', Icons.home_rounded),
    _Destination('History', Icons.history),
    _Destination('Zones', Icons.share_location),
    _Destination('Alerts', Icons.notifications_none),
    _Destination('Profile', Icons.person_outline),
  ];

  late final List<Widget> _pages = const [
    MapTab(),
    HistoryTab(),
    GeofenceTab(),
    AlertsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _pages.length; i++)
            _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        destinations: _destinations,
        currentIndex: _index,
        onTap: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Bottom navigation bar with a pill highlight on the active destination.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: context.colors.primaryContainer.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < destinations.length; i++)
                _NavItem(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.onPrimaryContainer : context.colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? context.colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(destination.icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(destination.label, style: AppText.labelMd.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
