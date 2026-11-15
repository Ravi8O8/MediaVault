import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/biometric_auth_service.dart';
import '../../core/database_service.dart';
import '../vault/vault_screen.dart';

class LockScreen extends StatefulWidget {
  final DatabaseService db;
  const LockScreen({super.key, required this.db});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    setState(() => _error = null);
    final ok = await BiometricAuthService.authenticate();
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VaultScreen(db: widget.db)),
      );
    } else {
      setState(() => _error = 'Не удалось подтвердить личность');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: GlassContainer.card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'MediaVault',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Заблокировано',
                    style: TextStyle(color: Colors.white54),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  GlassButton(
                    onPressed: _unlock,
                    child: const Text('Войти по отпечатку'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
