import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'core/utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  }
  runApp(const BodianaApp());
}

class BodianaApp extends StatelessWidget {
  const BodianaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bodiana',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: rootNavigatorKey,
      home: AppConfig.isConfigured ? const AuthGate() : const NotConfiguredScreen(),
    );
  }
}

class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This build of Bodiana has no server connection.\n\n'
            'Add SUPABASE_URL and SUPABASE_ANON_KEY as GitHub secrets (or pass them with --dart-define) and build again.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
