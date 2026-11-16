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
  bool _isAuthenticating = false;
  BiometricAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _checkAndAutoAttempt();
  }

  Future<void> _checkAndAutoAttempt() async {
    final a = await BiometricAuthService.checkAvailability();
    if (!mounted) return;
    setState(() => _availability = a);
    if (a == BiometricAvailability.available) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_isAuthenticating) return;
    setState(() {
      _error = null;
      _isAuthenticating = true;
    });

    final ok = await BiometricAuthService.authenticate();
    if (!mounted) return;

    setState(() => _isAuthenticating = false);

    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VaultScreen(db: widget.db)),
      );
    } else {
      setState(() => _error = 'Не удалось подтвердить личность');
    }
  }

  String get _hint {
    switch (_availability) {
      case BiometricAvailability.notEnrolled:
        return 'Биометрия не настроена.\nДобавьте отпечаток в настройках телефона.';
      case BiometricAvailability.notSupported:
        return 'Биометрия не поддерживается.\nУстановите PIN-код на устройстве.';
      case BiometricAvailability.available:
      case BiometricAvailability.unknown:
      case null:
        return 'Коснитесь для входа';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSupported = _availability != BiometricAvailability.notSupported;

    return Material(
      color: Colors.transparent,
      child: GlassScaffold(
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassContainer.card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 64, color: Colors.white70),
                    const SizedBox(height: 24),
                    const Text(
                      'MediaVault',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Хранилище заблокировано',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.white54),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 32),
                    if (_isAuthenticating)
                      const CircularProgressIndicator(color: Colors.tealAccent)
                    else if (isSupported)
                      GlassButton(
                        icon: const Icon(Icons.fingerprint,
                            color: Colors.white),
                        onTap: _unlock,
                      )
                    else
                      const Icon(Icons.lock, color: Colors.white38, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      _hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
