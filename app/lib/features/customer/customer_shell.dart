import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../shared/account_tab.dart';
import '../shared/requests_tab.dart';
import 'customer_home_tab.dart';
import 'favorites_tab.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: IndexedStack(index: _tab, children: [
          CustomerHomeTab(onOpenRequests: () => setState(() => _tab = 1)),
          const RequestsTab(asWorker: false),
          const FavoritesTab(),
          const AccountTab(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: context.t('nav_home')),
            NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: context.t('nav_requests')),
            NavigationDestination(icon: const Icon(Icons.favorite_border), selectedIcon: const Icon(Icons.favorite), label: context.t('nav_favorites')),
            NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.t('nav_account')),
          ],
        ),
    );
  }
}
