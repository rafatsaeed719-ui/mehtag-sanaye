import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/i18n/i18n.dart';
import 'data/repos/catalog_repo.dart';
import 'data/session.dart';
import 'features/customer/customer_location.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // يقرأ الإعدادات من android/app/google-services.json
  await Firebase.initializeApp();

  // كاش محلي لدعم الإنترنت الضعيف وفقد الاتصال
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 60 * 1024 * 1024,
  );

  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final locale = LocaleController();
  await locale.load();
  final session = Session();
  final catalog = CatalogRepo()..start();
  final customerLocation = CustomerLocation();
  await customerLocation.load();
  locale.onLangChanged((_, newLang) => session.onLanguageChanged(newLang));
  await session.start(locale.lang);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: locale),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: catalog),
      ChangeNotifierProvider.value(value: customerLocation),
    ],
    child: const MehtagSanayeApp(),
  ));
}
