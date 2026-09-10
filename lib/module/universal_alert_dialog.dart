import 'package:flutter/material.dart';

class UniversalAlertDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? contentWidget;
  final String? primaryButtonText;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryButtonText;
  final VoidCallback? onSecondaryPressed;
  final List<Widget>? customActions;

  const UniversalAlertDialog({
    super.key,
    required this.title,
    this.content,
    this.contentWidget,
    this.primaryButtonText,
    this.onPrimaryPressed,
    this.secondaryButtonText,
    this.onSecondaryPressed,
    this.customActions,
  }) : assert(
         content != null || contentWidget != null,
         'Provide either content or contentWidget.',
       );

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String content,
    String? primaryButtonText,
    VoidCallback? onPrimaryPressed,
    String? secondaryButtonText,
    VoidCallback? onSecondaryPressed,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => UniversalAlertDialog(
        title: title,
        content: content,
        primaryButtonText: primaryButtonText,
        onPrimaryPressed: onPrimaryPressed,
        secondaryButtonText: secondaryButtonText,
        onSecondaryPressed: onSecondaryPressed,
      ),
    );
  }

  void _handlePressed(BuildContext context, VoidCallback? callback) {
    Navigator.of(context).pop();
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    final dialogContent = contentWidget ?? Text(content!);
    if (customActions != null) {
      return AlertDialog(
        title: Text(title),
        content: dialogContent,
        actions: customActions,
      );
    }

    final actions = <Widget>[];
    if (secondaryButtonText != null) {
      actions.add(
        TextButton(
          onPressed: () => _handlePressed(context, onSecondaryPressed),
          child: Text(secondaryButtonText!),
        ),
      );
    }
    if (primaryButtonText != null) {
      actions.add(
        FilledButton(
          onPressed: () => _handlePressed(context, onPrimaryPressed),
          child: Text(primaryButtonText!),
        ),
      );
    }

    return AlertDialog(
      title: Text(title),
      content: dialogContent,
      actions: actions,
    );
  }
}
