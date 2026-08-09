import 'package:flutter/material.dart';
import 'package:para_v3/module/location_textfield.dart';
import 'package:para_v3/module/universal_map_tile.dart';
import 'package:para_v3/pages/commute_page_input.dart';

class CommutePage extends StatefulWidget {
  const CommutePage({super.key});

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _openInputPage(CommuteInputField initialField) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CommutePageInput(
          originController: _originController,
          destinationController: _destinationController,
          initialField: initialField,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const UniversalMapTile(),
        Positioned(
          top: 40,
          left: 8,
          right: 8,
          child: LocationTextfield(
            originController: _originController,
            destinationController: _destinationController,
            readOnly: true,
            onOriginTap: () => _openInputPage(CommuteInputField.origin),
            onDestinationTap: () =>
                _openInputPage(CommuteInputField.destination),
          ),
        ),
      ],
    );
  }
}
