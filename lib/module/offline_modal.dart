import 'package:flutter/material.dart';

final offlineScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Compatibility wrapper for the former offline modal presentation.
class OfflineModal {
  const OfflineModal._();

  static Future<void> show(BuildContext context) async {
    final messenger =
        offlineScaffoldMessengerKey.currentState ??
        ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('You are currently offline'),
          duration: const Duration(days: 365),
          action: SnackBarAction(
            label: 'CLOSE',
            onPressed: () {
              messenger.hideCurrentSnackBar();
            },
          ),
        ),
      );
  }
}
