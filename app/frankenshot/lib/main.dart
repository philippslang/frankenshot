import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  MachineConfig copyWith({
    double? timeBetweenBalls,
    int? speed,
    int? spin,
    int? height,
    int? horizontal,
  }) {
    return MachineConfig(
      timeBetweenBalls: timeBetweenBalls ?? this.timeBetweenBalls,
      speed: speed ?? this.speed,
      spin: spin ?? this.spin,
      height: height ?? this.height,
      horizontal: horizontal ?? this.horizontal,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeBetweenBalls': timeBetweenBalls,
        'speed': speed,
        'spin': spin,
        'height': height,
        'horizontal': horizontal,
      };

  factory MachineConfig.fromJson(Map<String, dynamic> json) => MachineConfig(
        timeBetweenBalls: (json['timeBetweenBalls'] as num).toDouble(),
        speed: json['speed'] as int,
        spin: json['spin'] as int,
        height: json['height'] as int,
        horizontal: json['horizontal'] as int,
      );
}

class ConfigList {
  final String name;
  final List<MachineConfig> configs;

  const ConfigList({
    required this.name,
    required this.configs,
  });

  ConfigList copyWith({
    String? name,
    List<MachineConfig>? configs,
  }) {
    return ConfigList(
      name: name ?? this.name,
      configs: configs ?? this.configs,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'configs': configs.map((c) => c.toJson()).toList(),
      };

  factory ConfigList.fromJson(Map<String, dynamic> json) => ConfigList(
        name: json['name'] as String,
        configs: (json['configs'] as List)
            .map((c) => MachineConfig.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class ConfigStorage {
  static const _configListsKey = 'config_lists';

  static Future<List<ConfigList>> loadConfigLists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_configListsKey);
    if (jsonString == null) {
      return _defaultConfigLists();
    }
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => ConfigList.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return _defaultConfigLists();
    }
  }

  static Future<void> saveConfigLists(List<ConfigList> configLists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(configLists.map((c) => c.toJson()).toList());
    await prefs.setString(_configListsKey, jsonString);
  }

  static List<ConfigList> _defaultConfigLists() => [
        const ConfigList(
          name: 'Warm Up',
          configs: [
            MachineConfig(
                timeBetweenBalls: 5.0,
                speed: 3,
                spin: 0,
                height: 5,
                horizontal: 0),
            MachineConfig(
                timeBetweenBalls: 4.0,
                speed: 4,
                spin: 0,
                height: 5,
                horizontal: 0),
            MachineConfig(
                timeBetweenBalls: 3.0,
                speed: 5,
                spin: 0,
                height: 5,
                horizontal: 0),
          ],
        ),
        const ConfigList(
          name: 'Topspin Practice',
          configs: [
            MachineConfig(
                timeBetweenBalls: 3.0,
                speed: 6,
                spin: 3,
                height: 6,
                horizontal: 0),
            MachineConfig(
                timeBetweenBalls: 3.0,
                speed: 6,
                spin: 4,
                height: 7,
                horizontal: -2),
            MachineConfig(
                timeBetweenBalls: 3.0,
                speed: 6,
                spin: 4,
                height: 7,
                horizontal: 2),
          ],
        ),
      ];
}

class MachineStatusScreen extends StatefulWidget {
  const MachineStatusScreen({super.key});

  @override
  State<MachineStatusScreen> createState() => _MachineStatusScreenState();
}

class _MachineStatusScreenState extends State<MachineStatusScreen> {
  bool _isFeeding = false;
  int _currentConfigIndex = 0;
  ConfigList? _selectedConfigList;
  List<ConfigList> _configLists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigLists();
  }

  Future<void> _loadConfigLists() async {
    final configs = await ConfigStorage.loadConfigLists();
    setState(() {
      _configLists = configs;
      _isLoading = false;
    });
  }

  Future<void> _saveConfigLists() async {
    await ConfigStorage.saveConfigLists(_configLists);
  }

  MachineConfig? get _currentConfig {
    if (_selectedConfigList == null || _selectedConfigList!.configs.isEmpty) {
      return null;
    }
    return _selectedConfigList!.configs[_currentConfigIndex % _selectedConfigList!.configs.length];
  }

  void _toggleFeeding() {
    setState(() {
      _isFeeding = !_isFeeding;
    });
  }

  void _manualFeed() {
    // TODO: Send manual feed command to machine
  }

  void _selectConfigList(ConfigList configList) {
    setState(() {
      _selectedConfigList = configList;
      _currentConfigIndex = 0;
      _isFeeding = false;
    });
  }

  void _createNewConfigList() async {
    final result = await Navigator.push<ConfigList>(
      context,
      MaterialPageRoute(
        builder: (context) => const ConfigListEditorScreen(),
      ),
    );
    if (result != null) {
      setState(() {
        _configLists.add(result);
      });
      _saveConfigLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Frankenshot'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  _buildCurrentConfigCard(),
                  const SizedBox(height: 24),
                  _buildConfigListsCard(),
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
            if (!_isFeeding) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _selectedConfigList != null ? _manualFeed : null,
                icon: const Icon(Icons.sports_tennis),
                label: const Text('Manual Feed'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigListsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Configuration Plans',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  onPressed: _createNewConfigList,
                  icon: const Icon(Icons.add),
                  tooltip: 'Create new',
                ),
              ],
            ),
            const Divider(),
            if (_configLists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('No configurations yet. Tap + to create one.'),
              )
            else
              ..._configLists.map((configList) => _buildConfigListTile(configList)),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigListTile(ConfigList configList) {
    final isSelected = _selectedConfigList?.name == configList.name;
    return ListTile(
      title: Text(
        configList.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text('${configList.configs.length} steps'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Chip(label: Text('Running'))
          else
            FilledButton.tonal(
              onPressed: () => _selectConfigList(configList),
              child: const Text('Run'),
            ),
          IconButton(
            onPressed: () => _deleteConfigList(configList),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  void _deleteConfigList(ConfigList configList) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text('Are you sure you want to delete "${configList.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _configLists.remove(configList);
        if (_selectedConfigList?.name == configList.name) {
          _selectedConfigList = null;
        }
      });
      _saveConfigLists();
    }
  }

  Widget _buildCurrentConfigCard() {
    final config = _currentConfig;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Configuration',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_selectedConfigList != null)
                  Text(
                    '${_currentConfigIndex + 1}/${_selectedConfigList!.configs.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
              ],
            ),
            const Divider(),
            _buildConfigRow(
              'Time Between Balls',
              config != null ? '${config.timeBetweenBalls} seconds' : '-',
              range: '1-11',
            ),
            _buildConfigRow(
              'Speed',
              config != null ? '${config.speed}' : '-',
              range: '0-10',
            ),
            _buildConfigRow(
              'Spin',
              config != null ? '${config.spin}' : '-',
              range: '-5 to 5',
            ),
            _buildConfigRow(
              'Height',
              config != null ? '${config.height}' : '-',
              range: '0-10',
            ),
            _buildConfigRow(
              'Horizontal',
              config != null ? '${config.horizontal}' : '-',
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

class ConfigListEditorScreen extends StatefulWidget {
  const ConfigListEditorScreen({super.key});

  @override
  State<ConfigListEditorScreen> createState() => _ConfigListEditorScreenState();
}

class _ConfigListEditorScreenState extends State<ConfigListEditorScreen> {
  final _nameController = TextEditingController();
  final List<MachineConfig> _configs = [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addConfig() async {
    final result = await showDialog<MachineConfig>(
      context: context,
      builder: (context) => const ConfigEditorDialog(),
    );
    if (result != null) {
      setState(() {
        _configs.add(result);
      });
    }
  }

  void _removeConfig(int index) {
    setState(() {
      _configs.removeAt(index);
    });
  }

  void _save() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }
    if (_configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one configuration')),
      );
      return;
    }
    Navigator.pop(
      context,
      ConfigList(name: _nameController.text, configs: _configs),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('New Plan'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'List Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Configurations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.icon(
                  onPressed: _addConfig,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_configs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'No plans yet.\nTap "Add" to create one.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...List.generate(_configs.length, (index) {
                final config = _configs[index];
                return Card(
                  child: ListTile(
                    title: Text('Config ${index + 1}'),
                    subtitle: Text(
                      'Speed: ${config.speed}, Spin: ${config.spin}, '
                      'Height: ${config.height}, Horizontal: ${config.horizontal}, '
                      'Time: ${config.timeBetweenBalls}s',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _removeConfig(index),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class ConfigEditorDialog extends StatefulWidget {
  const ConfigEditorDialog({super.key});

  @override
  State<ConfigEditorDialog> createState() => _ConfigEditorDialogState();
}

class _ConfigEditorDialogState extends State<ConfigEditorDialog> {
  double _timeBetweenBalls = 3.0;
  int _speed = 5;
  int _spin = 0;
  int _height = 5;
  int _horizontal = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Configuration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSlider(
              label: 'Time Between Balls',
              value: _timeBetweenBalls,
              min: 1,
              max: 11,
              divisions: 10,
              onChanged: (v) => setState(() => _timeBetweenBalls = v),
              displayValue: '${_timeBetweenBalls.toStringAsFixed(1)}s',
            ),
            _buildSlider(
              label: 'Speed',
              value: _speed.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _speed = v.round()),
              displayValue: '$_speed',
            ),
            _buildSlider(
              label: 'Spin',
              value: _spin.toDouble(),
              min: -5,
              max: 5,
              divisions: 10,
              onChanged: (v) => setState(() => _spin = v.round()),
              displayValue: '$_spin',
            ),
            _buildSlider(
              label: 'Height',
              value: _height.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _height = v.round()),
              displayValue: '$_height',
            ),
            _buildSlider(
              label: 'Horizontal',
              value: _horizontal.toDouble(),
              min: -5,
              max: 5,
              divisions: 10,
              onChanged: (v) => setState(() => _horizontal = v.round()),
              displayValue: '$_horizontal',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MachineConfig(
              timeBetweenBalls: _timeBetweenBalls,
              speed: _speed,
              spin: _spin,
              height: _height,
              horizontal: _horizontal,
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String displayValue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(displayValue, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
