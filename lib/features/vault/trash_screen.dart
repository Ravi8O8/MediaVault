import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';

/// Вкладка "Корзина". Уже без Scaffold — встраивается в оболочку VaultScreen.
class TrashScreen extends StatefulWidget {
  final DatabaseService db;
  const TrashScreen({super.key, required this.db});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getDeletedMediaItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _showItemMenu(Map<String, dynamic> item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF232526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.restore, color: Colors.tealAccent),
              title: const Text('Восстановить',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'restore'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text('Удалить навсегда',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (action == 'restore') {
      await widget.db.restoreMediaItem(item['id']);
      _load();
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF232526),
          title: const Text('Удалить навсегда?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Файл будет стерт с устройства безвозвратно.',
            style: TextStyle(color: Colors.white54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await widget.db
            .permanentlyDeleteMediaItem(item['id'], item['file_path']);
        _load();
      }
    }
  }

  Future<void> _emptyTrash() async {
    if (_items.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Очистить корзину?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Будет безвозвратно удалено файлов: ${_items.length}.',
          style: const TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.db.emptyTrash();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }
    return Stack(
      children: [
        if (_items.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Корзина пуста',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return GestureDetector(
                  onTap: () => _showItemMenu(item),
                  child: Opacity(
                    opacity: 0.6,
                    child: _TrashThumbnail(
                      filePath: item['file_path'],
                      isVideo: item['media_type'] == 'video',
                    ),
                  ),
                );
              },
            ),
          ),
        if (_items.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              label: const Text('Очистить',
                  style: TextStyle(color: Colors.white)),
              onPressed: _emptyTrash,
            ),
          ),
      ],
    );
  }
}

class _TrashThumbnail extends StatelessWidget {
  final String filePath;
  final bool isVideo;
  const _TrashThumbnail({required this.filePath, this.isVideo = false});

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.videocam, color: Colors.white54, size: 32),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _loadAndDecrypt(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
        );
      },
    );
  }

  Future<Uint8List> _loadAndDecrypt() async {
    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();
    return await CryptoService.decryptData(encryptedBytes);
  }
}
