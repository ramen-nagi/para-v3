import 'package:flutter/material.dart';
import 'package:para_v3/pages/reports_page.dart';

class ReportButton extends StatelessWidget {
  final String? routeId, tripId, fromStopId, toStopId, vehicleType;
  final double? expectedFare;
  final String? routeLongName, fromStopName, toStopName;

  const ReportButton({
    super.key,
    this.routeId,
    this.tripId,
    this.fromStopId,
    this.toStopId,
    this.vehicleType,
    this.expectedFare,
    this.routeLongName,
    this.fromStopName,
    this.toStopName,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Report a problem',
      icon: const Icon(Icons.report_problem_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportsPage(
            routeId: routeId,
            tripId: tripId,
            fromStopId: fromStopId,
            toStopId: toStopId,
            vehicleType: vehicleType,
            expectedFare: expectedFare,
            routeLongName: routeLongName,
            fromStopName: fromStopName,
            toStopName: toStopName,
          ),
        ),
      ),
    );
  }
}
