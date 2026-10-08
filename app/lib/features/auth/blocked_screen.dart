import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../data/session.dart';
import '../shared/help_screen.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.block, size: 72, color: AppColors.emergency),
              const SizedBox(height: 16),
              Text(context.t('account_blocked'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(context.t('account_blocked_sub'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
                child: Text(context.t('help_support')),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.read<Session>().signOut(), child: Text(context.t('logout'))),
            ]),
          ),
        ),
      );
}
