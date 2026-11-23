import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../customer/customer_shell.dart';
import '../customer/onboarding_screen.dart';
import '../vendor/vendor_onboarding_screen.dart';
import '../vendor/vendor_shell.dart';
import 'auth_screens.dart';
import 'welcome_screen.dart';

/// State shared between the login screens and the gate.
class LoginFlow {
  /// Role picked before Google sign-in (applied when the account has none).
  static String? pendingRole;

  /// Role of the login screen used; a mismatch signs the user out.
  static String? expectedRole;

  /// Message shown on the welcome screen after a forced sign-out.
  static String? flashMessage;
}

/// Bump to make the gate re-check where the user belongs (e.g. after onboarding).
final gateRefresh = ValueNotifier<int>(0);

enum _Dest { welcome, chooseRole, customerOnboarding, customer, vendorOnboarding, vendor }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  late Future<_Dest> _future;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = supa.auth.currentUser?.id;
    _future = _resolve();
    gateRefresh.addListener(_refresh);
    _sub = supa.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
        return;
      }
      final newUid = data.session?.user.id;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.signedOut) {
        rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
      if (newUid != _uid) {
        _uid = newUid;
        _refresh();
      }
    }, onError: (Object e) {
      LoginFlow.flashMessage = friendlyError(e);
      _refresh();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    gateRefresh.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _resolve());
  }

  Future<_Dest> _resolve() async {
    final user = supa.auth.currentUser;
    if (user == null) return _Dest.welcome;

    final profile = await supa.from('profiles').select().eq('id', user.id).maybeSingle();
    if (profile == null) {
      throw Exception('Your profile was not found. Make sure the Bodiana SQL setup was run in Supabase, then sign in again.');
    }
    var role = profile['role'] as String?;

    final pending = LoginFlow.pendingRole;
    LoginFlow.pendingRole = null;
    if (role == null && pending != null) {
      role = await supa.rpc('set_my_role', params: {'p_role': pending}) as String?;
    }

    final expected = LoginFlow.expectedRole;
    LoginFlow.expectedRole = null;
    if (role != null && expected != null && role != expected) {
      LoginFlow.flashMessage = 'This email is registered as a $role account. Please use the ${role == 'vendor' ? 'Vendor' : 'Customer'} login.';
      await supa.auth.signOut();
      return _Dest.welcome;
    }

    if (role == null) return _Dest.chooseRole;
    if (role == 'customer') {
      final cp = await supa.from('customer_profiles').select('onboarding_completed').eq('user_id', user.id).maybeSingle();
      return (cp != null && cp['onboarding_completed'] == true) ? _Dest.customer : _Dest.customerOnboarding;
    }
    final vp = await supa.from('vendor_profiles').select('id').eq('id', user.id).maybeSingle();
    return vp == null ? _Dest.vendorOnboarding : _Dest.vendor;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Dest>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SplashScreen();
        if (snap.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                ErrorView(message: friendlyError(snap.error), onRetry: _refresh),
                TextButton(onPressed: () => supa.auth.signOut(), child: const Text('Sign out')),
              ]),
            ),
          );
        }
        return switch (snap.data!) {
          _Dest.welcome => const WelcomeScreen(),
          _Dest.chooseRole => const ChooseRoleScreen(),
          _Dest.customerOnboarding => const CustomerOnboardingScreen(),
          _Dest.customer => const CustomerShell(),
          _Dest.vendorOnboarding => const VendorOnboardingScreen(),
          _Dest.vendor => const VendorShell(),
        };
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kMaroon,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          BodianaLogo(size: 96, light: true),
          SizedBox(height: 8),
          Text('Bengali wedding planning', style: TextStyle(color: kGold, letterSpacing: 1.2)),
          SizedBox(height: 32),
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: kGold, strokeWidth: 2)),
        ]),
      ),
    );
  }
}

/// Shown to Google users who have not picked Customer or Vendor yet.
class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});
  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  bool _busy = false;

  Future<void> _choose(String role) async {
    final ok = await confirmDialog(
      context,
      role == 'vendor' ? 'Continue as a vendor?' : 'Continue as a customer?',
      'An account can be either a customer or a vendor. This choice cannot be changed later.',
      confirm: 'Continue',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAction(context, () async {
      await supa.rpc('set_my_role', params: {'p_role': role});
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) gateRefresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 24),
            const BodianaLogo(size: 64),
            const SizedBox(height: 24),
            Text('How will you use Bodiana?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            RoleCard(
              icon: Icons.favorite,
              title: 'I am planning a wedding',
              subtitle: 'Plan events, discover vendors and send booking requests',
              onTap: _busy ? null : () => _choose('customer'),
            ),
            const SizedBox(height: 12),
            RoleCard(
              icon: Icons.storefront,
              title: 'I am a wedding vendor',
              subtitle: 'List services, manage packages and respond to enquiries',
              onTap: _busy ? null : () => _choose('vendor'),
            ),
            const Spacer(),
            TextButton(onPressed: () => supa.auth.signOut(), child: const Text('Sign out')),
          ]),
        ),
      ),
    );
  }
}
