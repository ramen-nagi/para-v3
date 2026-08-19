import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportCategory {
  routeNonexistent,
  incorrectRoutePath,
  wrongPlottedStop,
  fareDiscrepancy,
  appBugReport,
  others,
}

class ReportsPage extends StatefulWidget {
  final String? routeId, tripId, fromStopId, toStopId, vehicleType;
  final double? expectedFare;
  final String? routeLongName, fromStopName, toStopName;

  const ReportsPage({
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
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _routeId = TextEditingController();
  final _tripId = TextEditingController();
  final _fromId = TextEditingController();
  final _toId = TextEditingController();
  final _vehicle = TextEditingController();
  final _routeName = TextEditingController();
  final _fromName = TextEditingController();
  final _toName = TextEditingController();
  final _expected = TextEditingController();
  final _observed = TextEditingController();
  ReportCategory _category = ReportCategory.others;
  bool _submitting = false;

  static const _labels = {
    ReportCategory.routeNonexistent: 'Route nonexistent',
    ReportCategory.incorrectRoutePath: 'Incorrect route path',
    ReportCategory.wrongPlottedStop: 'Wrong plotted stop',
    ReportCategory.fareDiscrepancy: 'Fare discrepancy',
    ReportCategory.appBugReport: 'App bug report',
    ReportCategory.others: 'Others',
  };

  @override
  void initState() {
    super.initState();
    _set(_routeId, widget.routeId); _set(_tripId, widget.tripId);
    _set(_fromId, widget.fromStopId); _set(_toId, widget.toStopId);
    _set(_vehicle, widget.vehicleType); _set(_routeName, widget.routeLongName);
    _set(_fromName, widget.fromStopName); _set(_toName, widget.toStopName);
    if (widget.expectedFare != null) {
      _expected.text = widget.expectedFare!.toStringAsFixed(2);
    }
  }

  void _set(TextEditingController c, String? value) {
    if (value != null && value.isNotEmpty) c.text = value;
  }

  @override
  void dispose() {
    for (final c in [_description, _routeId, _tripId, _fromId, _toId,
      _vehicle, _routeName, _fromName, _toName, _expected, _observed]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final expected = double.tryParse(_expected.text.trim());
    final observed = double.tryParse(_observed.text.trim());
    if (_category == ReportCategory.fareDiscrepancy &&
        ((_expected.text.trim().isNotEmpty && expected == null) ||
         (_observed.text.trim().isNotEmpty && observed == null))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid fare amounts.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('reports').insert({
        'category': _categoryValue(_category),
        'description': _description.text.trim(),
        'route_id': _nullable(_routeId.text),
        'trip_id': _nullable(_tripId.text),
        'from_stop_id': _stopValue(_fromId.text, _fromName.text, '__ORIGIN__'),
        'to_stop_id': _stopValue(_toId.text, _toName.text, '__DESTINATION__'),
        'vehicle_type': _nullable(_vehicle.text),
        'expected_fare': expected,
        'observed_fare': observed,
        'reporter_id': user?.id,
        'platform': Theme.of(context).platform.name,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted successfully.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit report: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _categoryValue(ReportCategory value) => switch (value) {
    ReportCategory.routeNonexistent => 'route_nonexistent',
    ReportCategory.incorrectRoutePath => 'incorrect_route_path',
    ReportCategory.wrongPlottedStop => 'wrong_plotted_stop',
    ReportCategory.fareDiscrepancy => 'fare_discrepancy',
    ReportCategory.appBugReport => 'app_bug_report',
    ReportCategory.others => 'others',
  };

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
  String? _stopValue(String id, String name, String sentinel) =>
      id.trim() == sentinel ? _nullable(name) : _nullable(id);

  @override
  Widget build(BuildContext context) {
    final fare = _category == ReportCategory.fareDiscrepancy;
    return Scaffold(
      appBar: AppBar(title: const Text('Submit a Report')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<ReportCategory>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Report category', border: OutlineInputBorder()),
            items: _labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) { if (v != null) setState(() => _category = v); },
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _description, maxLines: 5, maxLength: 5000,
            decoration: const InputDecoration(labelText: 'Describe the problem', border: OutlineInputBorder()),
            validator: (v) => v == null || v.trim().isEmpty ? 'Please describe the problem' : null),
          const SizedBox(height: 16),
          _field(_routeName, 'Route'), _field(_fromName, 'From stop'),
          _field(_toName, 'To stop'), _field(_vehicle, 'Vehicle type'),
          if (fare) Row(children: [Expanded(child: _field(_expected, 'Expected fare')), const SizedBox(width: 12), Expanded(child: _field(_observed, 'Observed fare'))]),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _submitting ? null : _submit,
            icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
            label: Text(_submitting ? 'Submitting...' : 'Submit report')),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(controller: controller, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
  );
}
