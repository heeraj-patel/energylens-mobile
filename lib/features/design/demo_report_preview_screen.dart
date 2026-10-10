import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Local pilot presentation of the values already packaged on Devices.
class DemoReportPreviewScreen extends StatelessWidget {
  const DemoReportPreviewScreen({super.key});

  Future<List<(String, String, String)>> _items() async {
    final source = await rootBundle.loadString(
      'assets/design_pages/devices/app.html',
    );
    String value(int id) {
      final match = RegExp(
        'data-el-bind="devices_text_${id.toString().padLeft(3, '0')}"[^>]*>([^<]*)',
      ).firstMatch(source);
      return (match?.group(1) ?? '').replaceAll('&amp;', '&');
    }

    const bindings = <(int, int, int)>[
      (22, 26, 28),
      (29, 33, 35),
      (36, 40, 42),
      (43, 47, 49),
      (50, 54, 56),
      (57, 61, 63),
      (64, 68, 70),
      (71, 75, 77),
      (78, 82, 84),
      (85, 89, 91),
    ];
    return [
      for (final (name, useful, waste) in bindings)
        (value(name), value(useful), value(waste)),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Demo report preview')),
    body: SafeArea(
      child: FutureBuilder<List<(String, String, String)>>(
        future: _items(),
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('This is a sample preview. Nothing will be emailed.'),
            const SizedBox(height: 16),
            if (snapshot.hasData)
              for (final (name, useful, waste) in snapshot.data!)
                Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text('Useful: $useful    Waste: $waste'),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
