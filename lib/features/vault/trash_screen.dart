import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';

class TrashScreen extends StatefulWidget {
  final DatabaseService db;
  const TrashScreen({super.key, required this.db});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _deletedItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    final items = await widget.db.getDeletedMediaItems();
    if (mounted) {
      setState(() {
        _deletedItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _showItemOptions(Map<String, dynamic> item) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF232526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.restore, color: Colors.tealAccent),
                title: const Text('Восстановить', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.db.restoreMediaItem(item['id']);
                  await _loadTrash();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Удалить навсегда', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.db.permanentlyDeleteMediaItem(item['id'], item['file_path']);
                  await _loadTrash();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Очистить корзину?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Все файлы в корзине будут удалены навсегда. Это действие нельзя отменить.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await widget.db.emptyTrash();
      await _loadTrash();
    }
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
          title: const Text('Корзина'),
          actions: [
            if (_deletedItems.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                onPressed: _emptyTrash,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              top: kToolbarHeight + 8,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _deletedItems.isEmpty
                    ? Center(
                        child: Text(
                          'Корзина пуста',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _deletedItems.length,
                        itemBuilder: (context, index) {
                          final item = _deletedItems[index];
                          return GestureDetector(
                            onTap: () => _showItemOptions(item),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _EncryptedThumbnail(filePath: item['file_path']),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.white70),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}

class _EncryptedThumbnail extends StatelessWidget {
  final String filePath;
  const _EncryptedThumbnail({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _loadAndDecrypt(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.broken_image, color: Colors.redAccent),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: 0.5, // Делаем миниатюры в корзине полупрозрачными
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
            ),
          ),
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
