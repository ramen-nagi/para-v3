import 'package:flutter/material.dart';

class DragScrollSheet extends StatefulWidget {
  static final ValueNotifier<double> sheetExtent = ValueNotifier(0.22);

  final List<Widget> children;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<double> snapSizes;
  final bool snap;

  const DragScrollSheet({
    super.key,
    required this.children,
    this.initialChildSize = 0.22,
    this.minChildSize = 0.1,
    this.maxChildSize = 0.8,
    this.snapSizes = const [0.1, 0.22, 0.8],
    this.snap = true,
  });

  @override
  State<DragScrollSheet> createState() => _DragScrollSheetState();
}

class _DragScrollSheetState extends State<DragScrollSheet> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    DragScrollSheet.sheetExtent.value = widget.initialChildSize;
    _sheetController.addListener(_publishSheetExtent);
  }

  void _publishSheetExtent() {
    if (_sheetController.isAttached) {
      DragScrollSheet.sheetExtent.value = _sheetController.size;
    }
  }

  void _toggleSheetHeight() {
    final targetSize = _isExpanded
        ? widget.initialChildSize
        : widget.maxChildSize;
    setState(() => _isExpanded = !_isExpanded);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetController.isAttached) return;
      _sheetController.animateTo(
        targetSize,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _sheetController.removeListener(_publishSheetExtent);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: widget.initialChildSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      snapSizes: widget.snapSizes,
      snap: widget.snap,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              GestureDetector(
                onTap: _toggleSheetHeight,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    SizedBox(height: 4),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                ),
              ),
              ...widget.children,
            ],
          ),
        );
      },
    );
  }
}
