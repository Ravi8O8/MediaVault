import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';

class MediaViewerScreen extends StatefulWidget {
  final Map<String, dynamic> mediaItem;
  final DatabaseService db;

  const MediaViewerScreen({
    super.key,
    required this.mediaItem,
    required this.db,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.mediaItem['file_path']);
      final encryptedBytes = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encryptedBytes);
      if (mounted) {
        setState(() {
          _decryptedBytes = decrypted;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteItem() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Удалить файл?'),
        content: const Text('Файл будет перемещен в корзину.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.softDeleteMediaItem(widget.mediaItem['id']);
      if (mounted) {
        Navigator.pop(context); // Возвращаемся в хранилище
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteItem,
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.tealAccent)
            : _decryptedBytes == null
                ? const Text(
                    'Не удалось расшифровать файл',
                    style: TextStyle(color: Colors.redAccent),
                  )
                : InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      _decryptedBytes!,
                      fit: BoxFit.contain,
                    ),
                  ),
      ),
    );
  }
}
