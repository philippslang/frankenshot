import 'package:flutter/material.dart';

void main() {
  runApp(const FrankenshotApp());
}

class FrankenshotApp extends StatelessWidget {
  const FrankenshotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frankenshot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MachineStatusScreen(),
    );
  }
}

class MachineConfig {
  final double timeBetweenBalls;
  final int speed;
  final int spin;
  final int height;
  final int horizontal;

  const MachineConfig({
    required this.timeBetweenBalls,
    required this.speed,
    required this.spin,
    required this.height,
    required this.horizontal,
  });
}

class MachineStatusScreen extends StatefulWidget {
  const MachineStatusScreen({super.key});

  @override
  State<MachineStatusScreen> createState() => _MachineStatusScreenState();
}

class _MachineStatusScreenState extends State<MachineStatusScreen> {
  bool _isFeeding = true;

  final MachineConfig _config = const MachineConfig(
    timeBetweenBalls: 3.0,
    speed: 5,
    spin: 0,
    height: 5,
    horizontal: 0,
  );

  void _toggleFeeding() {
    setState(() {
      _isFeeding = !_isFeeding;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Frankenshot'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildConfigCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isFeeding ? Icons.play_circle : Icons.pause_circle,
                  size: 48,
                  color: _isFeeding ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                Text(
                  _isFeeding ? 'Feeding' : 'Paused',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: _isFeeding ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _toggleFeeding,
              icon: Icon(_isFeeding ? Icons.pause : Icons.play_arrow),
              label: Text(_isFeeding ? 'Pause' : 'Resume'),
              style: FilledButton.styleFrom(
                backgroundColor: _isFeeding ? Colors.orange : Colors.green,
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            _buildConfigRow(
              'Time Between Balls',
              '${_config.timeBetweenBalls} seconds',
            ),
            _buildConfigRow(
              'Speed',
              '${_config.speed}',
              range: '0-10',
            ),
            _buildConfigRow(
              'Spin',
              '${_config.spin}',
              range: '-5 to 5',
            ),
            _buildConfigRow(
              'Height',
              '${_config.height}',
              range: '0-10',
            ),
            _buildConfigRow(
              'Horizontal',
              '${_config.horizontal}',
              range: '-5 to 5',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigRow(String label, String value, {String? range}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (range != null)
                Text(
                  range,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
            ],
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
