import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme.dart';
import '../../data/session.dart';
import 'language_toggle.dart';

/// شاشة الترحيب: اللوجو + رسالة بسيطة + «ابدأ دلوقتي» → اختيار (عميل / صنايعي)
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _scroll = ScrollController();
  bool _showRoles = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _showRoles = true);
    Future.delayed(const Duration(milliseconds: 280), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.navy, AppColors.navyDark],
          ),
        ),
        child: SafeArea(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            children: [
              const Align(alignment: AlignmentDirectional.centerEnd, child: LanguageToggle(light: true)),
              const SizedBox(height: 4),
              Center(
                child: Container(
                  width: 190,
                  height: 190,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [AppColors.amber, Color(0xFFFF6A00)]),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: ClipOval(child: Image.asset('assets/images/brand_logo_round.png', fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 22),
              Text(context.t('welcome_hello'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.3)),
              const SizedBox(height: 10),
              Text(context.t('welcome_tagline'),
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.amber, fontSize: 17, fontWeight: FontWeight.w800, height: 1.4)),
              const SizedBox(height: 12),
              Text(context.t('welcome_body'),
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, height: 1.65)),
              const SizedBox(height: 20),
              _Feature(emoji: '📍', text: context.t('welcome_f1')),
              _Feature(emoji: '⭐', text: context.t('welcome_f2')),
              _Feature(emoji: '📲', text: context.t('welcome_f3')),
              const SizedBox(height: 18),
              Text(context.t('welcome_slogan'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, child: child)),
                child: _showRoles ? _roles(context) : _startButton(context),
              ),
              const SizedBox(height: 18),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white60),
                  onPressed: () => context.read<Session>().chooseRole('admin'),
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  label: Text(context.t('admin_login')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _startButton(BuildContext context) => SizedBox(
        key: const ValueKey('start'),
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          onPressed: _start,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(context.t('start_now')),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded),
          ]),
        ),
      );

  Widget _roles(BuildContext context) => Column(
        key: const ValueKey('roles'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.t('choose_how'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
          const SizedBox(height: 10),
          _RoleButton(
            emoji: '👤',
            label: context.t('role_customer_btn'),
            filled: true,
            onTap: () => context.read<Session>().chooseRole('customer'),
          ),
          const SizedBox(height: 12),
          _RoleButton(
            emoji: '🔧',
            label: context.t('role_worker_btn'),
            filled: false,
            onTap: () => context.read<Session>().chooseRole('worker'),
          ),
        ],
      );
}

class _Feature extends StatelessWidget {
  final String emoji, text;
  const _Feature({required this.emoji, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
      );
}

class _RoleButton extends StatelessWidget {
  final String emoji, label;
  final bool filled;
  final VoidCallback onTap;
  const _RoleButton({required this.emoji, required this.label, required this.filled, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: filled ? AppColors.amber : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: filled ? Colors.white : AppColors.navy)),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: filled ? Colors.white : AppColors.navy),
            ]),
          ),
        ),
      );
}
