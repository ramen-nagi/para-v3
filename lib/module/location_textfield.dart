import 'package:flutter/material.dart';

class LocationTextfield extends StatelessWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;
  final FocusNode? originFocusNode;
  final FocusNode? destinationFocusNode;
  final VoidCallback? onOriginTap;
  final VoidCallback? onDestinationTap;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;
  final bool readOnly;

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
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMarker(Colors.blue),
                const SizedBox(height: 7),
                for (var index = 0; index < 3; index++) ...[
                  const Icon(Icons.circle, size: 4, color: Colors.grey),
                  if (index < 2) const SizedBox(height: 3),
                ],
                const SizedBox(height: 7),
                _buildMarker(Colors.red),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  _buildTextField(
                    controller: originController,
                    focusNode: originFocusNode,
                    hintText: 'Origin',
                    onTap: onOriginTap,
                    onChanged: onOriginChanged,
                  ),
                  const SizedBox(height: 18),
                  _buildTextField(
                    controller: destinationController,
                    focusNode: destinationFocusNode,
                    hintText: 'Destination',
                    onTap: onDestinationTap,
                    onChanged: onDestinationChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Column(
              children: [
                Icon(Icons.report_problem_outlined),
                SizedBox(height: 20),
                Icon(Icons.swap_vert),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarker(Color color) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    FocusNode? focusNode,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            border: InputBorder.none,
            suffixIcon: value.text.isEmpty
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
        );
      },
    );
  }
}
