import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

enum ControlCommand { forward, backward, left, right, craneUp, craneDown, craneRotateLeft, craneRotateRight }

void main() => runApp(const CraneRemoteApp());

class CraneRemoteApp extends StatelessWidget {
  const CraneRemoteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Crane Remote Control',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFB300), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF111820)),
    home: const RemoteScreen(),
  );
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  static const String _broker = 'broker.hivemq.com';
  static const int _port = 8883;
  final _deviceController = TextEditingController(text: 'car1');
  late String _clientId;
  MqttServerClient? _client;
  Timer? _retryTimer;
  bool _connected = false;
  bool _connecting = false;
  final Map<ControlCommand, String> _activeTopics = {};

  @override
  void initState() {
    super.initState();
    _clientId = _newClientId();
    _connect();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_connected && !_connecting) _connect();
    });
  }

  String _newClientId() => 'crane_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  String _commandName(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward: return 'forward';
      case ControlCommand.backward: return 'backward';
      case ControlCommand.left: return 'left';
      case ControlCommand.right: return 'right';
      case ControlCommand.craneUp: return 'crane_up';
      case ControlCommand.craneDown: return 'crane_down';
      case ControlCommand.craneRotateLeft: return 'crane_rotate_left';
      case ControlCommand.craneRotateRight: return 'crane_rotate_right';
    }
  }

  String _topic(ControlCommand c) => 'cranecar/${_deviceController.text.trim()}/cmd/${_commandName(c)}';

  Future<void> _connect() async {
    if (_connecting || !mounted) return;
    setState(() => _connecting = true);
    _client?.disconnect();
    final client = MqttServerClient.withPort(_broker, _clientId, _port);
    client.secure = true;
    client.keepAlivePeriod = 30;
    client.logging(on: false);
    client.onConnected = () {
      if (!mounted) return;
      setState(() { _connected = true; _connecting = false; _activeTopics.clear(); });
    };
    client.onDisconnected = () {
      if (!mounted) return;
      setState(() { _connected = false; _connecting = false; _activeTopics.clear(); });
    };
    client.connectionMessage = MqttConnectMessage().withClientIdentifier(_clientId).startClean().withWillQos(MqttQos.atMostOnce);
    _client = client;
    try {
      await client.connect();
      if (!mounted) return;
      setState(() {
        _connected = client.connectionStatus?.state == MqttConnectionState.connected;
        _connecting = false;
      });
    } catch (_) {
      client.disconnect();
      if (!mounted) return;
      setState(() { _connected = false; _connecting = false; });
    }
  }

  void _publish(String topic, String value) {
    final client = _client;
    if (!_connected || client == null) return;
    final payload = MqttClientPayloadBuilder()..addString(value);
    client.publishMessage(topic, MqttQos.atMostOnce, payload.payload!);
  }

  void _press(ControlCommand c) {
    if (_activeTopics.containsKey(c)) return;
    HapticFeedback.selectionClick();
    final topic = _topic(c);
    _activeTopics[c] = topic;
    _publish(topic, '1');
  }

  void _release(ControlCommand c) {
    final topic = _activeTopics.remove(c);
    if (topic != null) _publish(topic, '0');
  }

  Future<void> _reconnect() async {
    if (_connecting) return;
    final old = _client;
    _client = null;
    _connected = false;
    old?.disconnect();
    await _connect();
  }

  Future<void> _newIdAndReconnect() async {
    setState(() => _clientId = _newClientId());
    await _reconnect();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    for (final topic in _activeTopics.values.toList()) { _publish(topic, '0'); }
    _activeTopics.clear();
    _client?.disconnect();
    _deviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _connected ? const Color(0xFF35D07F) : const Color(0xFFFF5D5D);
    return Scaffold(
      appBar: AppBar(title: const Text('CRANE / CAR REMOTE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)), centerTitle: true),
      body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Column(children: [
        Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: Column(children: [
          Row(children: [Icon(Icons.circle, size: 12, color: statusColor), const SizedBox(width: 8), Expanded(child: Text(_connected ? 'Connected · $_broker:$_port (TLS)' : _connecting ? 'Connecting to $_broker…' : 'Disconnected · $_broker:$_port')), IconButton(tooltip: 'Reconnect', onPressed: _connecting ? null : _reconnect, icon: const Icon(Icons.refresh))]),
          Row(children: [const Icon(Icons.precision_manufacturing_outlined, size: 19), const SizedBox(width: 8), const Text('Device ID'), const SizedBox(width: 8), Expanded(child: TextField(controller: _deviceController, autocorrect: false, decoration: const InputDecoration(isDense: true, hintText: 'must match ESP8266', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8))))]),
          Row(children: [const Icon(Icons.tag, size: 19), const SizedBox(width: 8), const Text('Client ID'), const SizedBox(width: 8), Expanded(child: Text(_clientId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))), IconButton(tooltip: 'Generate client ID and reconnect', onPressed: _connecting ? null : _newIdAndReconnect, icon: const Icon(Icons.shuffle))]),
        ]))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('HOLD A CONTROL TO MOVE · RELEASE TO STOP', style: TextStyle(color: Color(0xFF9EADB8), fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700))),
        Expanded(child: Row(children: [
          Expanded(child: ControlPad(title: 'DRIVE', icon: Icons.directions_car_filled, accent: const Color(0xFFFFB300), commands: const [ControlCommand.forward, ControlCommand.backward, ControlCommand.left, ControlCommand.right], onPress: _press, onRelease: _release)),
          const SizedBox(width: 10),
          Expanded(child: ControlPad(title: 'CRANE ARM', icon: Icons.precision_manufacturing, accent: const Color(0xFF40C4FF), commands: const [ControlCommand.craneUp, ControlCommand.craneDown, ControlCommand.craneRotateLeft, ControlCommand.craneRotateRight], onPress: _press, onRelease: _release)),
        ])),
        const SizedBox(height: 6),
        const Text('ESP8266 subscribes to: cranecar/<device-id>/cmd/#', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF84939E), fontSize: 11)),
      ]))),
    );
  }
}

class ControlPad extends StatelessWidget {
  const ControlPad({required this.title, required this.icon, required this.accent, required this.commands, required this.onPress, required this.onRelease, super.key});
  final String title;
  final IconData icon;
  final Color accent;
  final List<ControlCommand> commands;
  final ValueChanged<ControlCommand> onPress;
  final ValueChanged<ControlCommand> onRelease;

  String _label(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward: return 'FORWARD';
      case ControlCommand.backward: return 'BACKWARD';
      case ControlCommand.left: return 'LEFT';
      case ControlCommand.right: return 'RIGHT';
      case ControlCommand.craneUp: return 'UP';
      case ControlCommand.craneDown: return 'DOWN';
      case ControlCommand.craneRotateLeft: return 'ROTATE L';
      case ControlCommand.craneRotateRight: return 'ROTATE R';
    }
  }
  IconData _buttonIcon(ControlCommand c) {
    switch (c) {
      case ControlCommand.forward: case ControlCommand.craneUp: return Icons.arrow_upward;
      case ControlCommand.backward: case ControlCommand.craneDown: return Icons.arrow_downward;
      case ControlCommand.left: case ControlCommand.craneRotateLeft: return Icons.arrow_back;
      case ControlCommand.right: case ControlCommand.craneRotateRight: return Icons.arrow_forward;
    }
  }
  @override
  Widget build(BuildContext context) => Card(color: const Color(0xFF1B252E), clipBehavior: Clip.antiAlias, child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: accent, size: 19), const SizedBox(width: 6), Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w800, letterSpacing: 1.2))]),
    const SizedBox(height: 8),
    Expanded(child: GridView.count(physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, children: commands.map((c) => _MomentaryButton(label: _label(c), icon: _buttonIcon(c), accent: accent, onDown: () => onPress(c), onUp: () => onRelease(c))).toList())),
  ])));
}

class _MomentaryButton extends StatelessWidget {
  const _MomentaryButton({required this.label, required this.icon, required this.accent, required this.onDown, required this.onUp});
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onDown;
  final VoidCallback onUp;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => onDown(),
    onTapUp: (_) => onUp(),
    onTapCancel: onUp,
    child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF26343F), border: Border.all(color: accent.withOpacity(0.75), width: 2), boxShadow: [BoxShadow(color: accent.withOpacity(0.12), blurRadius: 12, spreadRadius: 1)]), child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: accent, size: 27), const SizedBox(height: 3), FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4)))])))),
  );
}
