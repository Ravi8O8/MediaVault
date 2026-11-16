// ... импорты добавь:
import '../../core/ui_helpers.dart';

// ... внутри _cleanGroup и _cleanAll замени вызовы:

  Future<void> _cleanGroup(Map<String, dynamic> g) async {
    final ids = _membersOf(g);
    if (ids.length < 2) return;
    for (int i = 1; i < ids.length; i++) {
      // ... (код удаления)
    }
    await _reload();
    if (mounted) {
      showAppSnackBar(context, 'Оставлена 1 из ${ids.length} копий');
    }
  }

  Future<void> _cleanAll() async {
    int totalDeleted = 0;
    // ... (цикл)
    await _reload();
    if (mounted && totalDeleted > 0) {
      showAppSnackBar(context, 'Удалено копий: $totalDeleted');
    }
  }
