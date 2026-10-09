import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/i18n/i18n.dart';
import 'core/theme.dart';
import 'core/widgets/common.dart';
import 'data/models.dart';
import 'data/services/in_app_notifier.dart';
import 'data/session.dart';
import 'features/admin/admin_shell.dart';
import 'features/auth/blocked_screen.dart';
import 'features/auth/complete_profile_screen.dart';
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
      // على الكمبيوتر: التطبيق يظهر بعرض موبايل في النص
      builder: kIsWeb
          ? (context, child) => ColoredBox(
                color: AppColors.navyDark,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ClipRect(child: child ?? const SizedBox()),
                  ),
                ),
              )
          : null,
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
  String? _listeningFor;

  @override
  void initState() {
    super.initState();
    _fg = InAppNotifier.instance.incoming.stream.listen(_showBanner);
  }

  @override
  void dispose() {
    _fg?.cancel();
    super.dispose();
  }

  void _showBanner(AppNotification n) {
    final lang = context.read<LocaleController>().lang;
    final (title, body) = notificationText(n, lang);
    final urgent = n.type == 'emergency_request';
    messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: urgent ? const Color(0xFFDC2626) : null,
      duration: Duration(seconds: urgent ? 10 : 5),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (body.isNotEmpty) Text(body),
      ]),
      action: n.data['requestId'] != null
          ? SnackBarAction(label: context.read<LocaleController>().t('ok'), textColor: Colors.white, onPressed: () => _openFromNotification(n.data))
          : null,
    ));
  }

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

  void _syncNotifier(Session s) {
    final uid = (s.state == SessionState.customer || s.state == SessionState.worker || s.state == SessionState.workerOnboarding) ? s.uid : null;
    if (uid == _listeningFor) return;
    _listeningFor = uid;
    if (uid == null) {
      InAppNotifier.instance.stop();
    } else {
      InAppNotifier.instance.start(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    _syncNotifier(s);
    switch (s.state) {
      case SessionState.loading:
        return const Scaffold(body: LoadingView());
      case SessionState.chooseRole:
        return const WelcomeScreen();
      case SessionState.signedOut:
        return const LoginScreen();
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
      case SessionState.admin:
        return const AdminShell();
    }
  }
}
