import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/i18n/i18n.dart';
import 'core/theme.dart';
import 'core/widgets/common.dart';
import 'data/services/push_service.dart';
import 'data/session.dart';
import 'features/auth/blocked_screen.dart';
import 'features/auth/complete_profile_screen.dart';
import 'features/auth/link_phone_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/customer/customer_shell.dart';
import 'features/shared/chat_screen.dart';
import 'features/shared/request_details_screen.dart';
import 'features/worker/application_status_screen.dart';
import 'features/worker/wallet_screen.dart';
import 'features/worker/worker_shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class MehtagSanayeApp extends StatelessWidget {
  const MehtagSanayeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>();
    return MaterialApp(
      // تغيير اللغة يعيد بناء التطبيق بالكامل (RTL ↔ LTR)
      key: ValueKey(locale.lang),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: locale.t('app_name'),
      theme: buildTheme(),
      locale: locale.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// يحدد الشاشة الرئيسية حسب حالة المستخدم
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  StreamSubscription? _fg;
  StreamSubscription? _opened;

  @override
  void initState() {
    super.initState();
    _fg = PushService.instance.foreground.stream.listen(_showBanner);
    _opened = PushService.instance.opened.stream.listen(_openFromNotification);
  }

  @override
  void dispose() {
    _fg?.cancel();
    _opened?.cancel();
    super.dispose();
  }

  void _showBanner(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.title ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        if ((n.body ?? '').isNotEmpty) Text(n.body!),
      ]),
      action: m.data['requestId'] != null
          ? SnackBarAction(label: locale().t('ok'), onPressed: () => _openFromNotification(m.data))
          : null,
    ));
  }

  LocaleController locale() => context.read<LocaleController>();

  void _openFromNotification(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final rid = data['requestId']?.toString();
    final screen = data['screen']?.toString();
    if (screen == 'chat' && rid != null) {
      nav.push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: rid)));
    } else if (rid != null) {
      nav.push(MaterialPageRoute(builder: (_) => RequestDetailsScreen(requestId: rid)));
    } else if (screen == 'wallet' && context.read<Session>().isWorker) {
      nav.push(MaterialPageRoute(builder: (_) => const WalletScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    switch (s.state) {
      case SessionState.loading:
        return const Scaffold(body: LoadingView());
      case SessionState.chooseRole:
        return const WelcomeScreen();
      case SessionState.signedOut:
        return const LoginScreen();
      case SessionState.needsPhone:
        return const LinkPhoneScreen();
      case SessionState.needsProfile:
        return const CompleteProfileScreen();
      case SessionState.blocked:
        return const BlockedScreen();
      case SessionState.customer:
        return const CustomerShell();
      case SessionState.workerOnboarding:
        return const ApplicationStatusScreen();
      case SessionState.worker:
        return const WorkerShell();
    }
  }
}
