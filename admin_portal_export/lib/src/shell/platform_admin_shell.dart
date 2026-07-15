import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/presentation/admin_auth_providers.dart';

class PlatformAdminShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const PlatformAdminShell({
    required this.child,
    required this.location,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final selectedIndex =
        location.startsWith('/settings')
            ? 5
            : location.startsWith('/support')
            ? 4
            : location.startsWith('/addons')
            ? 3
            : location.startsWith('/plans')
            ? 2
            : location.startsWith('/tenants')
            ? 1
            : 0;
    final navigation = NavigationRail(
      extended: wide,
      selectedIndex: selectedIndex,
      onDestinationSelected:
          (index) => context.go(switch (index) {
            1 => '/tenants',
            2 => '/plans',
            3 => '/addons',
            4 => '/support',
            5 => '/settings',
            _ => '/',
          }),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.workspace_premium_outlined),
          selectedIcon: Icon(Icons.workspace_premium),
          label: Text('Plans'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: Text('Tenants'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.extension_outlined),
          selectedIcon: Icon(Icons.extension),
          label: Text('Add-ons'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.support_agent_outlined),
          selectedIcon: Icon(Icons.support_agent),
          label: Text('Audit & support'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Shop Platform Admin'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed:
                () => ref.read(adminLoginControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          if (wide) navigation,
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar:
          wide
              ? null
              : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected:
                    (index) => context.go(switch (index) {
                      1 => '/tenants',
                      2 => '/plans',
                      3 => '/addons',
                      4 => '/support',
                      5 => '/settings',
                      _ => '/',
                    }),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'Dashboard',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.workspace_premium_outlined),
                    selectedIcon: Icon(Icons.workspace_premium),
                    label: 'Plans',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront),
                    label: 'Tenants',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.extension_outlined),
                    selectedIcon: Icon(Icons.extension),
                    label: 'Add-ons',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.support_agent_outlined),
                    selectedIcon: Icon(Icons.support_agent),
                    label: 'Support',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
    );
  }
}
