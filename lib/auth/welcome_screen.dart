import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'auth_gate.dart';
import 'auth_screens.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final msg = LoginFlow.flashMessage;
      if (msg != null && mounted) {
        LoginFlow.flashMessage = null;
        showSnack(context, msg, error: true);
      }
    });
  }

  void _open(String role) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginScreen(role: role)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kMaroon, Color(0xFF7D1A30), kIvory],
            stops: [0, 0.45, 0.45],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const BodianaLogo(size: 88, light: true),
              const SizedBox(height: 8),
              const Text(
                'Plan every ritual, from Aiburo Bhat to Bou Bhat,\nand book trusted vendors in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFF6E7C1), height: 1.4),
              ),
              const SizedBox(height: 56),
              Text('Continue as', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              RoleCard(
                icon: Icons.favorite,
                title: 'Customer',
                subtitle: 'Plan your wedding, discover vendors and send booking requests',
                onTap: () => _open('customer'),
              ),
              const SizedBox(height: 12),
              RoleCard(
                icon: Icons.storefront,
                title: 'Vendor',
                subtitle: 'Manage your business, services, packages and bookings',
                onTap: () => _open('vendor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const RoleCard({super.key, required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
          child: Icon(icon, color: kMaroon),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 13)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: kMaroon),
      ]),
    );
  }
}
