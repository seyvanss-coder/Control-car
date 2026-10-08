import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() => runApp(const CraneApp());

const kBroker = 'broker.hivemq.com';
const kPort = 8883;

class CraneApp extends StatelessWidget {
  const CraneApp({super.key});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
      home: const RemoteScreen(),
    );
  }
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  MqttServerClient? client;
  bool connected = false;
  String device = 'esp8266';
  Timer? pubTimer;
  final Map<String, String> state = {'x': '0', 'y': '0', 'c': '0', 'r': '0'};

  Future<void> connect() async {
    final c = MqttServerClient(kBroker, 'crane_${DateTime.now().millisecondsSinceEpoch}');
    c.port = kPort;
    c.secure = true;
    c.loggingOn = false;
    c.onConnected = () => setState(() => connected = true);
    c.onDisconnected = () => setState(() => connected = false);
    try {
      await c.connect();
      c.subscribe('#');
    } catch (_) {
      setState(() => connected = false);
    }
  }

  void send(String topic, String val) {
    if (state[topic] == val) return;
    state[topic] = val;
    final c = client;
    if (c == null || !connected) return;
    final b = MqttClientPayloadBuilder();
    b.addString(val);
    c.publishMessage('cranecar/$device/cmd/$topic', MqttQos.atMostOnce, b.payload!);
  }

  void stopAll() {
    for (final t in ['x', 'y', 'c', 'r']) {
      state[t] = '0';
      send(t, '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8ECF2),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFFF7F9FC), Color(0xFFDDE4EE)]),
          ),
          child: Column(children: [
            _topBar(),
            Expanded(child: Row(children: [
              Expanded(child: _side(left: true)),
              Expanded(child: _center()),
              Expanded(child: _side(left: false)),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(children: [
      _lampDot(connected),
      const SizedBox(width: 6),
      _lampDot(connected),
      const Spacer(),
      Text(connected ? 'CONNECTED' : 'TAP TO CONNECT',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
              color: connected ? Colors.blue.shade700 : Colors.grey)),
      const SizedBox(width: 12),
      GestureDetector(
        onTap: () { if (!connected) connect(); else stopAll(); },
        child: Icon(connected ? Icons.power_settings_new : Icons.bluetooth_searching,
            color: connected ? Colors.blue.shade700 : Colors.blueGrey),
      ),
    ]),
  );

  Widget _lampDot(bool on) => Container(
    width: 14, height: 14,
    decoration: BoxDecoration(shape: BoxShape.circle,
      color: on ? Colors.lightBlue : Colors.grey.shade400,
      boxShadow: on ? [BoxShadow(color: Colors.lightBlue.withOpacity(.8), blurRadius: 8, spreadRadius: 1)] : []),
  );

  Widget _side({required bool left}) => Center(
    child: Joystick3D(
      color: left ? Colors.blue.shade700 : Colors.blue.shade500,
      label: left ? 'CAR' : 'CRANE',
      onMove: (dx, dy) {
        if (left) { send('x', dx.round().toString()); send('y', (-dy).round().toString()); }
        else { send('c', (-dy).round().toString()); send('r', dx.round().toString()); }
      },
    ),
  );

  Widget _center() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _padBtn('▲', 'fwd'), _padBtn('▼', 'bwd'),
    ]),
    const SizedBox(height: 8),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _shapeBtn('△', Colors.green.shade600, 'horn'),
      const SizedBox(width: 8),
      _shapeBtn('✕', Colors.red.shade600, 'stop'),
    ]),
  ]);

  Widget _padBtn(String icon, String cmd) => GestureDetector(
    onLongPressStart: (_) => send(icon == '▲' ? 'x' : 'y', icon == '▲' ? '100' : '-100'),
    onLongPressEnd: (_) => stopAll(),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: 56, height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF20242E),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 3), blurRadius: 6)],
      ),
      child: Center(child: Text(icon, style: const TextStyle(color: Colors.white, fontSize: 18))),
    ),
  );

  Widget _shapeBtn(String symbol, Color color, String cmd) => GestureDetector(
    onTapDown: (_) => send(cmd, '1'),
    onTapUp: (_) => send(cmd, '0'),
    child: Container(
      width: 48, height: 48,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF20242E),
        boxShadow: [BoxShadow(color: Colors.black26, offset: Offset(0, 3), blurRadius: 6)]),
      child: Center(child: Text(symbol, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold))),
    ),
  );
}

// ---------- 3D Joystick ----------
class Joystick3D extends StatefulWidget {
  final Color color;
  final String label;
  final void Function(double dx, double dy) onMove;
  const Joystick3D({super.key, required this.color, required this.label, required this.onMove});
  @override
  State<Joystick3D> createState() => _Joystick3DState();
}

class _Joystick3DState extends State<Joystick3D> {
  Offset offset = Offset.zero;
  static const r = 52.0;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.label, style: TextStyle(fontWeight: FontWeight.bold, color: widget.color, fontSize: 13)),
      const SizedBox(height: 8),
      Listener(
        onPointerDown: (_) {},
        onPointerMove: (e) => _update(e.localPosition),
        onPointerUp: (_) {
          setState(() => offset = Offset.zero);
          widget.onMove(0, 0);
        },
        child: GestureDetector(
          onPanUpdate: (d) => _update(d.localPosition),
          child: Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFFF2F5FA), Color(0xFFCBD3E0)]),
              boxShadow: [BoxShadow(color: Colors.grey.shade500.withOpacity(.5), offset: const Offset(0, 6), blurRadius: 12)],
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Stack(alignment: Alignment.center, children: [
              // knob with 3D shadow
              Positioned(
                left: 75 - r + offset.dx, top: 75 - r + offset.dy,
                child: Container(
                  width: r * 2, height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Colors.white, widget.color.withOpacity(.85)]),
                    boxShadow: [BoxShadow(color: widget.color.withOpacity(.45), offset: const Offset(0, 5), blurRadius: 10)],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  void _update(Offset p) {
    final c = const Offset(75, 75);
    var v = p - c;
    final len = v.distance;
    if (len > 58) v = v / len * 58;
    setState(() => offset = v);
    widget.onMove((v.dx / 58 * 100).clamp(-100, 100).toDouble(), (v.dy / 58 * 100).clamp(-100, 100).toDouble());
  }
}
