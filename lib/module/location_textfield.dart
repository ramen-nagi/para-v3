import 'package:flutter/material.dart';
import 'package:para_v3/module/report_button.dart';

class LocationTextfield extends StatelessWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;
  final FocusNode? originFocusNode;
  final FocusNode? destinationFocusNode;
  final VoidCallback? onOriginTap;
  final VoidCallback? onDestinationTap;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;
  final VoidCallback? onSwap;
  final bool readOnly;
  final bool showClearButton;
  final bool showTrailingActions;

  const LocationTextfield({
    super.key,
    required this.originController,
    required this.destinationController,
    this.originFocusNode,
    this.destinationFocusNode,
    this.onOriginTap,
    this.onDestinationTap,
    this.onOriginChanged,
    this.onDestinationChanged,
    this.onSwap,
    this.readOnly = false,
    this.showClearButton = true,
    this.showTrailingActions = false,
  });

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required Color markerColor,
    FocusNode? focusNode,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return ListenableBuilder(
          listenable: focusNode ?? controller,
          builder: (context, child) {
            final isFocused = focusNode?.hasFocus ?? false;
            final colorScheme = Theme.of(context).colorScheme;
            return SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: readOnly,
                onTap: onTap,
                onChanged: onChanged,
                maxLines: 1,
                minLines: 1,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: isFocused
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.surface,
                  constraints: const BoxConstraints.tightFor(height: 48),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 10),
                    child: Icon(
                      Icons.location_on,
                      color: markerColor,
                      size: 28,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 46,
                    minHeight: 48,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant,
                      width: 1.25,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant,
                      width: 1.25,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 48,
                    maxWidth: 48,
                    minHeight: 48,
                    maxHeight: 48,
                  ),
                  suffixIcon: value.text.isEmpty || !showClearButton
                      ? null
                      : IconButton(
                          tooltip: 'Clear $hintText',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            controller.clear();
                            onChanged?.call('');
                            focusNode?.requestFocus();
                          },
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _buildTextField(
                    controller: originController,
                    focusNode: originFocusNode,
                    hintText: 'Start Location',
                    markerColor: const Color(0xFF1687F8),
                    onTap: onOriginTap,
                    onChanged: onOriginChanged,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: destinationController,
                    focusNode: destinationFocusNode,
                    hintText: 'Target Destination',
                    markerColor: const Color(0xFFFF3B43),
                    onTap: onDestinationTap,
                    onChanged: onDestinationChanged,
                  ),
                ],
              ),
            ),
            if (showTrailingActions) ...[
              const SizedBox(width: 10),
              Column(
                children: [
                  const SizedBox.square(dimension: 48, child: ReportButton()),
                  const SizedBox(height: 12),
                  SizedBox.square(
                    dimension: 48,
                    child: IconButton(
                      tooltip: 'Swap origin and destination',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: onSwap,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
