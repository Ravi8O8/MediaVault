import 'package:flutter/material.dart';

void showAppSnackBar(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars(); // Убираем старые сообщения из очереди
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2), // Исчезает через 2 сек
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Colors.redAccent : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
