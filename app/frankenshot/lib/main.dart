import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FrankenshotApp());
}

class BleService {
  static const String _deviceAddress = '80:B5:4E:D5:F8:4A';
  static const String _serviceUuid = '01544f48-534e-454b-4e41-524600000000';
  static const String _currentConfigCharUuid = '01544f48-534e-454b-4e41-524601000000';
  static const String _feedingCharUuid = '01544f48-534e-454b-4e41-524602000000';
  static const String _manualFeedCharUuid = '01544f48-534e-454b-4e41-524603000000';
  static const String _programCharUuid = '01544f48-534e-454b-4e41-524604000000';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _currentConfigCharacteristic;
  BluetoothCharacteristic? _feedingCharacteristic;
  BluetoothCharacteristic? _manualFeedCharacteristic;
  BluetoothCharacteristic? _programCharacteristic;
  int _programId = 0;
  StreamSubscription<List<int>>? _currentConfigSubscription;
  StreamSubscription<List<int>>? _feedingSubscription;

  final _connectionStateController = StreamController<bool>.broadcast();
  final _feedingStateController = StreamController<bool>.broadcast();
  final _currentConfigController = StreamController<MachineConfig>.broadcast();

  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<bool> get feedingState => _feedingStateController.stream;
  Stream<MachineConfig> get currentConfig => _currentConfigController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      _device = BluetoothDevice.fromId(_deviceAddress);
      await _device!.connect(timeout: const Duration(seconds: 10));
      _isConnected = true;
      _connectionStateController.add(true);

      await _discoverServices();
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      rethrow;
    }
  }

  Future<void> _discoverServices() async {
    if (_device == null) return;

    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toLowerCase() == _serviceUuid.toLowerCase()) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == _currentConfigCharUuid.toLowerCase()) {
            _currentConfigCharacteristic = char;
          } else if (uuid == _feedingCharUuid.toLowerCase()) {
            _feedingCharacteristic = char;
          } else if (uuid == _manualFeedCharUuid.toLowerCase()) {
            _manualFeedCharacteristic = char;
          } else if (uuid == _programCharUuid.toLowerCase()) {
            _programCharacteristic = char;
          }
        }
        await _setupCurrentConfigNotifications();
        await _setupFeedingNotifications();
        break;
      }
    }
  }

  Future<void> _setupCurrentConfigNotifications() async {
    if (_currentConfigCharacteristic == null) return;

    // Read initial value
    final value = await _currentConfigCharacteristic!.read();
    _parseAndBroadcastConfig(value);

    // Subscribe to notifications
    await _currentConfigCharacteristic!.setNotifyValue(true);
    _currentConfigSubscription =
        _currentConfigCharacteristic!.onValueReceived.listen(_parseAndBroadcastConfig);
  }

  void _parseAndBroadcastConfig(List<int> value) {
    if (value.length < 5) return;

    // Parse bytes: speed, height, time_between_balls, spin, horizontal
    // spin and horizontal are 0-10 in payload, map to -5 to 5
    final config = MachineConfig(
      speed: value[0],
      height: value[1],
      timeBetweenBalls: value[2],
      spin: value[3] - 5, // 0-10 → -5 to 5
      horizontal: value[4] - 5, // 0-10 → -5 to 5
    );
    _currentConfigController.add(config);
  }

  Future<void> _setupFeedingNotifications() async {
    if (_feedingCharacteristic == null) return;

    // Read initial value
    final value = await _feedingCharacteristic!.read();
    if (value.isNotEmpty) {
      _feedingStateController.add(value[0] == 1);
    }

    // Subscribe to notifications
    await _feedingCharacteristic!.setNotifyValue(true);
    _feedingSubscription = _feedingCharacteristic!.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        _feedingStateController.add(value[0] == 1);
      }
    });
  }

  Future<void> setFeeding(bool feeding) async {
    if (_feedingCharacteristic == null) return;
    await _feedingCharacteristic!.write([feeding ? 1 : 0]);
  }

  Future<void> manualFeed() async {
    if (_manualFeedCharacteristic == null) return;
    await _manualFeedCharacteristic!.write([0]);
  }

  Future<void> sendProgram(ConfigList configList) async {
    if (_programCharacteristic == null) return;

    // Limit to 8 configs max
    final configs = configList.configs.take(8).toList();
    final count = configs.length;

    // Build payload: id (1 byte) + count (1 byte) + configs (5 bytes each)
    final payload = <int>[
      _programId++ & 0xFF, // id, wraps around at 255
      count,
    ];

    for (final config in configs) {
      payload.addAll([
        config.speed,
        config.height,
        config.timeBetweenBalls,
        config.spin + 5, // -5 to 5 → 0 to 10
        config.horizontal + 5, // -5 to 5 → 0 to 10
      ]);
    }

    await _programCharacteristic!.write(payload);
  }

  Future<void> disconnect() async {
    await _currentConfigSubscription?.cancel();
    await _feedingSubscription?.cancel();
    await _device?.disconnect();
    _isConnected = false;
    _connectionStateController.add(false);
  }

  void dispose() {
    _currentConfigSubscription?.cancel();
    _feedingSubscription?.cancel();
    _connectionStateController.close();
    _feedingStateController.close();
    _currentConfigController.close();
  }
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
  final int timeBetweenBalls;
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
    int? timeBetweenBalls,
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
        timeBetweenBalls: (json['timeBetweenBalls'] as num).toInt(),
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
          name: 'Easy DTL',
          configs: [
            MachineConfig(
                timeBetweenBalls: 5,
                speed: 3,
                spin: 2,
                height: 5,
                horizontal: 0),
          ],
        ),
        const ConfigList(
          name: 'Easy FH/BH',
          configs: [
            MachineConfig(
                timeBetweenBalls: 5,
                speed: 3,
                spin: 2,
                height: 5,
                horizontal: 3),
            MachineConfig(
                timeBetweenBalls: 5,
                speed: 3,
                spin: 2,
                height: 5,
                horizontal: -3),
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

  final BleService _bleService = BleService();
  bool _isConnected = false;
  bool _isConnecting = false;
  MachineConfig? _bleCurrentConfig;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<bool>? _feedingSubscription;
  StreamSubscription<MachineConfig>? _currentConfigSubscription;

  @override
  void initState() {
    super.initState();
    _loadConfigLists();
    _setupBle();
  }

  void _setupBle() {
    _connectionSubscription = _bleService.connectionState.listen((connected) {
      setState(() {
        _isConnected = connected;
        _isConnecting = false;
        if (!connected) {
          _bleCurrentConfig = null;
        }
      });
    });

    _feedingSubscription = _bleService.feedingState.listen((feeding) {
      setState(() {
        _isFeeding = feeding;
      });
    });

    _currentConfigSubscription = _bleService.currentConfig.listen((config) {
      setState(() {
        _bleCurrentConfig = config;
      });
    });

    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
    });
    try {
      await _bleService.connect();
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _feedingSubscription?.cancel();
    _currentConfigSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
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
    // When connected, show the actual config from the device
    if (_isConnected && _bleCurrentConfig != null) {
      return _bleCurrentConfig;
    }
    // Otherwise show the selected config list's current config
    if (_selectedConfigList == null || _selectedConfigList!.configs.isEmpty) {
      return null;
    }
    return _selectedConfigList!.configs[_currentConfigIndex % _selectedConfigList!.configs.length];
  }

  void _toggleFeeding() async {
    if (!_isConnected) return;
    await _bleService.setFeeding(!_isFeeding);
  }

  void _manualFeed() {
    if (!_isConnected) return;
    _bleService.manualFeed();
  }

  void _selectConfigList(ConfigList configList) async {
    setState(() {
      _selectedConfigList = configList;
      _currentConfigIndex = 0;
    });

    if (_isConnected) {
      await _bleService.sendProgram(configList);
    }
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

  void _editConfigList(ConfigList configList) async {
    final result = await Navigator.push<ConfigList>(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigListEditorScreen(existingConfig: configList),
      ),
    );
    if (result != null) {
      setState(() {
        final index = _configLists.indexOf(configList);
        if (index != -1) {
          _configLists[index] = result;
          if (_selectedConfigList?.name == configList.name) {
            _selectedConfigList = result;
          }
        }
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
        actions: [
          _buildConnectionIndicator(),
        ],
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

  Widget _buildConnectionIndicator() {
    if (_isConnecting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      onPressed: _isConnected ? null : _connect,
      icon: Icon(
        _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
        color: _isConnected ? Colors.blue : Colors.grey,
      ),
      tooltip: _isConnected ? 'Connected' : 'Tap to connect',
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
                  _isConnected
                      ? (_isFeeding ? Icons.play_circle : Icons.pause_circle)
                      : Icons.bluetooth_disabled,
                  size: 48,
                  color: _isConnected
                      ? (_isFeeding ? Colors.green : Colors.orange)
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  _isConnected
                      ? (_isFeeding ? 'Feeding' : 'Paused')
                      : 'Disconnected',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: _isConnected
                            ? (_isFeeding ? Colors.green : Colors.orange)
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isConnected)
              FilledButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: const Icon(Icons.bluetooth),
                label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              )
            else ...[
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
                  onPressed: _manualFeed,
                  icon: const Icon(Icons.sports_tennis),
                  label: const Text('Manual Feed'),
                ),
              ],
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
            onPressed: () => _editConfigList(configList),
            icon: const Icon(Icons.edit_outlined),
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
  final ConfigList? existingConfig;

  const ConfigListEditorScreen({super.key, this.existingConfig});

  @override
  State<ConfigListEditorScreen> createState() => _ConfigListEditorScreenState();
}

class _ConfigListEditorScreenState extends State<ConfigListEditorScreen> {
  final _nameController = TextEditingController();
  final List<MachineConfig> _configs = [];

  bool get _isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingConfig != null) {
      _nameController.text = widget.existingConfig!.name;
      _configs.addAll(widget.existingConfig!.configs);
    }
  }

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
        title: Text(_isEditing ? 'Edit Plan' : 'New Plan'),
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
  int _timeBetweenBalls = 3;
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
              value: _timeBetweenBalls.toDouble(),
              min: 1,
              max: 11,
              divisions: 10,
              onChanged: (v) => setState(() => _timeBetweenBalls = v.round()),
              displayValue: '${_timeBetweenBalls}s',
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
