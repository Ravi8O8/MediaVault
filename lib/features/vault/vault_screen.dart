import 'package:flutter/material.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/database_service.dart';

class VaultScreen extends StatefulWidget {
  final DatabaseService db;
  const VaultScreen({super.key, required this.db});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  // Временно ставим false, чтобы ты мог делать скриншоты для отладки
  bool _secure = false;

  @override
  void initState() {
    super.initState();
    // ВНИМАНИЕ: Блокировка скриншотов временно отключена!
    // Когда приложение будет готово, раскомментируй строку ниже и поменяй _secure на true:
    // FlutterWindowManagerPlus.setSecure(true);
    FlutterWindowManagerPlus.setSecure(false);
  }

  @override
  void dispose() {
    // При выходе тоже снимаем блокировку
    FlutterWindowManagerPlus.setSecure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GlassScaffold(
        background: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF232526), Color(0xFF414345)],
            ),
          ),
        ),
        appBar: GlassAppBar(
          title: const Text('Хранилище'),
          actions: [
            IconButton(
              icon: Icon(_secure ? Icons.visibility_off : Icons.visibility),
              onPressed: () {
                setState(() {
                  _secure = !_secure;
                  FlutterWindowManagerPlus.setSecure(_secure);
                });
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              GlassContainer.card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  // Используем Row с Expanded, чтобы блоки не вылезали за края
                  child: Row(
                    children: const [
                      Expanded(
                        child: _StatChip(icon: Icons.photo, label: 'Фото'),
                      ),
                      Expanded(
                        child: _StatChip(icon: Icons.video_library, label: 'Видео'),
                      ),
                      Expanded(
                        child: _StatChip(icon: Icons.folder, label: 'Альбомы'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Text(
                    'Здесь будет медиа-сетка',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(height: 4),
        // FittedBox автоматически уменьшит текст, если он не влезает
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}
