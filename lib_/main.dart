
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

enum ControlCommand {
  forward,
  backward,
  left,
  right,
  craneUp,
  craneDown,
  craneRotateLeft,
  craneRotateRight,
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CraneRemoteApp());
}

class CraneRemoteApp extends StatelessWidget {
  const CraneRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFB300);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crane Remote',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1118),
        cardColor: const Color(0xFF151F2A),
      ),
      home: const RemoteScreen(),
    );
  }
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen>
    with WidgetsBindingObserver {
  static const String _broker = 'broker.hivemq.com';
  static const int _port = 8883;

  final _deviceController = TextEditingController(text: 'car1');

  late String _clientId;
  MqttServerClient? _client;
  Timer? _retryTimer;

  bool _connected = false;
  bool _connecting = false;
  bool _disposed = false;

  final Map<ControlCommand, String> _activeTopics = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _clientId = _newClientId();
    _connect();

    _retryTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!_connected && !_connecting && !_disposed) {
          _connect();
        }
      },
    );
  }

  String _newClientId() =>
      'crane_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  String _commandName(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward:
        return 'forward';
      case ControlCommand.backward:
        return 'backward';
      case ControlCommand.left:
        return 'left';
      case ControlCommand.right:
        return 'right';
      case ControlCommand.craneUp:
        return 'crane_up';
      case ControlCommand.craneDown:
        return 'crane_down';
      case ControlCommand.craneRotateLeft:
        return 'crane_rotate_left';
      case ControlCommand.craneRotateRight:
        return 'crane_rotate_right';
    }
  }

  String _topic(ControlCommand c) {
    final id = _deviceController.text.trim();

    if (id.isEmpty || id.contains('/')) {
      throw ArgumentError('Device ID is invalid');
    }

    return 'cranecar/$id/cmd/${_commandName(c)}';
  }

  Future<void> _connect() async {
    if (_connecting || _disposed) return;

    _connecting = true;
    if (mounted) setState(() {});

    final previous = _client;
    _client = null;
    previous?.disconnect();

    final client = MqttServerClient.withPort(
      _broker,
      _clientId,
      _port,
    );

    client.secure = true;
    client.keepAlivePeriod = 30;
    client.connectTimeoutPeriod = 8000;
    client.logging(on: false);

    client.onConnected = () {
      if (_disposed || !identical(_client, client)) return;

      if (mounted) {
        setState(() {
          _connected = true;
          _connecting = false;
        });
      }
    };

    client.onDisconnected = () {
      if (_disposed || !identical(_client, client)) return;

      _activeTopics.clear();

      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
        });
      }
    };

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _client = client;

    try {
      final status = await client.connect();

      if (_disposed || !identical(_client, client)) return;

      final success =
          status?.state == MqttConnectionState.connected;

      if (!success) {
        client.disconnect();
      }

      if (mounted) {
        setState(() {
          _connected = success;
          _connecting = false;
        });
      }
    } catch (_) {
      client.disconnect();

      if (_disposed || !identical(_client, client)) return;

      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
        });
      }
    }
  }

  bool _publish(String topic, String value) {
    final client = _client;

    if (!_connected ||
        client == null ||
        client.connectionStatus?.state !=
            MqttConnectionState.connected) {
      return false;
    }

    try {
      final builder = MqttClientPayloadBuilder()
        ..addString(value);

      final payload = builder.payload;
      if (payload == null) return false;

      client.publishMessage(
        topic,
        MqttQos.atMostOnce,
        payload,
        retain: false,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  void _press(ControlCommand command) {
    if (!_connected || _activeTopics.containsKey(command)) {
      return;
    }

    try {
      final topic = _topic(command);

      if (_publish(topic, '1')) {
        _activeTopics[command] = topic;
        HapticFeedback.selectionClick();
        if (mounted) setState(() {});
      }
    } catch (_) {
      _showMessage('شناسه دستگاه معتبر نیست.');
    }
  }

  void _release(ControlCommand command) {
    final topic = _activeTopics.remove(command);
    if (topic == null) return;

    _publish(topic, '0');

    if (mounted) setState(() {});
  }

  void _releaseAll() {
    final topics = _activeTopics.values.toList();
    _activeTopics.clear();

    for (final topic in topics) {
      _publish(topic, '0');
    }

    if (mounted) setState(() {});
  }

  Future<void> _reconnect() async {
    if (_connecting || _disposed) return;

    _releaseAll();

    final old = _client;
    _client = null;
    _connected = false;
    _connecting = false;

    old?.disconnect();

    await _connect();
  }

  Future<void> _applyDeviceId() async {
    final id = _deviceController.text.trim();

    if (id.isEmpty || id.contains('/')) {
      _showMessage('شناسه دستگاه معتبر نیست.');
      return;
    }

    await _reconnect();
  }

  Future<void> _newIdAndReconnect() async {
    if (_connecting) return;

    _clientId = _newClientId();
    if (mounted) setState(() {});

    await _reconnect();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _releaseAll();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();

    for (final topic in _activeTopics.values.toList()) {
      _publish(topic, '0');
    }

    _activeTopics.clear();
    _client?.disconnect();
    _deviceController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFB300);
    const blue = Color(0xFF40C4FF);

    final statusColor = _connected
        ? const Color(0xFF35D07F)
        : const Color(0xFFFF5D5D);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CRANE / CAR',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Reconnect',
            onPressed: _connecting ? null : _reconnect,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF151F2A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: statusColor,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _connected
                                ? 'MQTT CONNECTED'
                                : _connecting
                                    ? 'CONNECTING...'
                                    : 'DISCONNECTED',
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(Icons.wifi, color: gold),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _deviceController,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _applyDeviceId(),
                      decoration: InputDecoration(
                        labelText: 'Device ID',
                        hintText: 'car1',
                        prefixIcon: const Icon(
                          Icons.precision_manufacturing,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Apply device ID',
                          onPressed:
                              _connecting ? null : _applyDeviceId,
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.tag,
                          size: 18,
                          color: blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _clientId,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'New client ID',
                          onPressed: _connecting
                              ? null
                              : _newIdAndReconnect,
                          icon: const Icon(Icons.shuffle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'HOLD TO MOVE • RELEASE TO STOP',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9EADB8),
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ControlPad(
                        title: 'DRIVE',
                        icon: Icons.directions_car_filled,
                        accent: gold,
                        commands: const [
                          ControlCommand.forward,
                          ControlCommand.backward,
                          ControlCommand.left,
                          ControlCommand.right,
                        ],
                        onPress: _press,
                        onRelease: _release,
                        activeCommands: _activeTopics.keys.toSet(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ControlPad(
                        title: 'CRANE',
                        icon: Icons.precision_manufacturing,
                        accent: blue,
                        commands: const [
                          ControlCommand.craneUp,
                          ControlCommand.craneDown,
                          ControlCommand.craneRotateLeft,
                          ControlCommand.craneRotateRight,
                        ],
                        onPress: _press,
                        onRelease: _release,
                        activeCommands: _activeTopics.keys.toSet(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _activeTopics.isEmpty
                      ? null
                      : _releaseAll,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('RELEASE ALL CONTROLS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'cranecar/<device-id>/cmd/#',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF84939E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ControlPad extends StatelessWidget {
  const ControlPad({
    required this.title,
    required this.icon,
    required this.accent,
    required this.commands,
    required this.onPress,
    required this.onRelease,
    required this.activeCommands,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<ControlCommand> commands;
  final ValueChanged<ControlCommand> onPress;
  final ValueChanged<ControlCommand> onRelease;
  final Set<ControlCommand> activeCommands;

  String _label(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward:
        return 'FORWARD';
      case ControlCommand.backward:
        return 'BACKWARD';
      case ControlCommand.left:
        return 'LEFT';
      case ControlCommand.right:
        return 'RIGHT';
      case ControlCommand.craneUp:
        return 'UP';
      case ControlCommand.craneDown:
        return 'DOWN';
      case ControlCommand.craneRotateLeft:
        return 'ROTATE L';
      case ControlCommand.craneRotateRight:
        return 'ROTATE R';
    }
  }

  IconData _buttonIcon(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward:
      case ControlCommand.craneUp:
        return Icons.arrow_upward;
      case ControlCommand.backward:
      case ControlCommand.craneDown:
        return Icons.arrow_downward;
      case ControlCommand.left:
      case ControlCommand.craneRotateLeft:
        return Icons.arrow_back;
      case ControlCommand.right:
      case ControlCommand.craneRotateRight:
        return Icons.arrow_forward;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF151F2A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 19),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 0.85,
              children: commands.map((command) {
                return _MomentaryButton(
                  label: _label(command),
                  icon: _buttonIcon(command),
                  accent: accent,
                  active: activeCommands.contains(command),
                  onDown: () => onPress(command),
                  onUp: () => onRelease(command),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentaryButton extends StatelessWidget {
  const _MomentaryButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.active,
    required this.onDown,
    required this.onUp,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool active;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: active
              ? accent.withOpacity(0.22)
              : const Color(0xFF202E3B),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: accent.withOpacity(active ? 1 : 0.65),
            width: active ? 2.5 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(active ? 0.25 : 0.07),
              blurRadius: active ? 14 : 6,
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accent, size: 27),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
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
}
