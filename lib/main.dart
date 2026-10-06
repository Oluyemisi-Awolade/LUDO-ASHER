// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'services/support_purchase_service.dart';
import 'widgets/support_thanks.dart';

/// Lets the thank-you popup appear on any screen.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase, then activate App Check. This must happen before
  // anything else touches Firebase. Play Integrity attests that requests
  // come from this real, untampered app — this pairs with the manual
  // X-Firebase-AppCheck header sent on every request in firebase_service.dart.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

  // Start listening for support purchases right away so any purchase that
  // completes later (delayed payment, app restart) is still processed, and
  // show the thank-you popup anywhere in the app.
  SupportPurchaseService.instance.start();
  SupportThanks.init(navigatorKey);

  // Force portrait — Ludo boards don't benefit from landscape on phones.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0D1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: LudoAsherApp()));
}

class LudoAsherApp extends StatelessWidget {
  const LudoAsherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo Asher',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LoginScreen(),
      builder: (context, child) => MediaQuery(
        // Clamp font scale — prevents layout breaks on large-text
        // accessibility settings.
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: 0.8, maxScaleFactor: 1.2),
        ),
        child: child!,
      ),
    );
  }
}
