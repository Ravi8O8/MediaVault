import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/hash_service.dart';
import '../../core/thumbnail_cache.dart';

class DuplicatesScreen extends StatefulWidget {
  final DatabaseService db;
  const DuplicatesScreen({super.key, required this.db});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  bool _scanning = false;
  int _processed = 0;
  int _total = 0;
  String _stage = '';

  List<Map<String, dynamic>> _groups = [];

  Future<void> _scanHashes() async {
    setState(() {
      _scanning = true;
      _stage = 'Поиск неотхэшированных файлов…';
      _processed = 0;
      _total = 0;
    });

    final without = await widget.db.getActiveMediaWithoutHash();
    if (!mounted) return;
    setState(() {
      _total = without.length;
      _stage = 'Хэширование $_total файлов…';
    });

    for (int i = 0; i < without.length; i++) {
      final row = without[i];
      try {
        final id = row['id'] as int;
        final path = row['file_path'] as String;
        final file = File(path);
        if (!await file.exists()) continue;
        final enc = await file.readAsBytes();
        final dec = await CryptoService.decryptData(enc);
        final hash = await HashService.hashDecryptedBytes(dec);
        if (hash.isNotEmpty) {
          await widget.db.setFileHash(id, hash);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _processed = i + 1;
        _stage = 'Хэширование $_processed / $_total';
      });
    }

    final groups = await widget.db.findDuplicateGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _scanning = false;
      _stage = '';
    });
  }

  Future<void> _reload() async {
    final groups = await widget.db.findDuplicateGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  List<int> _membersOf(Map<String, dynamic> g) {
    final raw = g['ids'] as String? ?? '';
    return raw.split(',').where((e) => e.isNotEmpty).map(int.parse).toList();
  }

  Future<void> _cleanGroup(Map<String, dynamic> g) async {
    final ids = _membersOf(g);
    if (ids.length < 2) return;
    for (int i = 1; i < ids.length; i++) {
      final id = ids[i];
      final rows = await widget.db.db.query(
        'media_items',
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final path = rows.first['file_path'] as String;
      await widget.db.softDeleteMediaItem(id);
      ThumbnailCache.evict(path);
    }
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Оставлена 1 из ${ids.length} копий')),
      );
    }
  }

  Future<void> _cleanAll() async {
    for (final g in List.of(_groups)) {
      await _cleanGroup(g);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Дубликаты'),
        actions: [
          if (_groups.isNotEmpty && !_scanning)
            IconButton(
              tooltip: 'Оставить по одному',
              icon: const Icon(Icons.auto_delete_outlined),
              onPressed: _cleanAll,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
          child: Column(
            children: [
              if (_scanning) ...[
                LinearProgressIndicator(
                  value: _total == 0 ? null : _processed / _total,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation(Colors.tealAccent),
                ),
                const SizedBox(height: 8),
                Text(_stage,
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _scanHashes,
                  icon: const Icon(Icons.search),
                  label: Text(_groups.isEmpty
                      ? 'Найти дубликаты'
                      : 'Пересчитать заново'),
                ),
                const SizedBox(height: 16),
                if (_groups.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Дубликатов нет.\nНажмите «Найти», чтобы просканировать файлы.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final g = _groups[i];
                        final count = g['cnt'] as int;
                        return _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Найдено копий: $count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _cleanGroup(g),
                                  icon: const Icon(
                                    Icons.delete_sweep_outlined,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Оставить 1 копию',
                                    style:
                                        TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}
