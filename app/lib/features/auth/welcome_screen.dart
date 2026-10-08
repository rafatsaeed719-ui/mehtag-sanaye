import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../data/session.dart';
import 'language_toggle.dart';

/// أول شاشة: محتاج صنايعي؟ / أنت صنايعي؟
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            const Align(alignment: AlignmentDirectional.centerEnd, child: LanguageToggle(light: true)),
            const SizedBox(height: 12),
            Center(child: Image.asset('assets/images/logo_mark.png', width: 110, height: 110)),
            const SizedBox(height: 16),
            Text(context.t('welcome_title'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(context.t('welcome_sub'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 32),
            _RoleCard(
              emoji: '👤',
              title: context.t('i_am_customer'),
              subtitle: context.t('i_am_customer_sub'),
              steps: [context.t('customer_steps1'), context.t('customer_steps2'), context.t('customer_steps3'), context.t('customer_steps4')],
              onTap: () => context.read<Session>().chooseRole('customer'),
            ),
            const SizedBox(height: 16),
            _RoleCard(
              emoji: '🔧',
              title: context.t('i_am_worker'),
              subtitle: context.t('i_am_worker_sub'),
              steps: [context.t('worker_step1'), context.t('worker_step2'), context.t('worker_step3'), context.t('worker_step4')],
              accent: AppColors.amber,
              onTap: () => context.read<Session>().chooseRole('worker'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final List<String> steps;
  final VoidCallback onTap;
  final Color accent;
  const _RoleCard({required this.emoji, required this.title, required this.subtitle, required this.steps, required this.onTap, this.accent = Colors.white});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: accent == Colors.white ? AppColors.amberSoft : accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)),
                    Text(subtitle, style: const TextStyle(color: AppColors.muted)),
                  ]),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: AppColors.muted),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final s in steps)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(s, style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
                  ),
              ]),
            ]),
          ),
        ),
      );
}
