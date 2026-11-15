import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/database_service.dart';

class VaultScreen extends StatefulWidget {
  final DatabaseService db;
  const VaultScreen({super.key, required this.db});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _secure = true;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
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
            onPressed: () => setState(() => _secure = !_secure),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    _StatChip(icon: Icons.photo, label: 'Фото'),
                    _StatChip(icon: Icons.video_library, label: 'Видео'),
                    _StatChip(icon: Icons.folder, label: 'Альбомы'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Text(
                  'Здесь будет медиа-сетка',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ),
            ),
          ],
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
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }
}
