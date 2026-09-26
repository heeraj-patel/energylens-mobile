import 'package:flutter/material.dart';

void main() => runApp(const EnergyLensApp());

class EnergyLensApp extends StatelessWidget {
  const EnergyLensApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EnergyLens',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7659))),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EnergyLens')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt, size: 48),
              SizedBox(height: 20),
              Text('Understand your electricity use',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('Connect a monitored computer to see measured power, cost, and useful actions.'),
              SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No device connected', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Live readings will appear here after the hub is connected.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
