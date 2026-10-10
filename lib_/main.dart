import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CraneRemoteApp());
}

class CraneRemoteApp extends StatelessWidget {
  const CraneRemoteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF17C9B5),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF101820),
          useMaterial3: true,
        ),
        home: const RemotePage(),
      );
}

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  static const String _host = 'broker.hivemq.com';
  static const int _port = 8883;
  static const String _deviceId = 'car1';
  static const String _driveTopic = 'cranecar/car1/cmd/drive';
  static const String _craneTopic = 'cranecar/car1/cmd/crane';

  MqttServerClient? _client;
  Timer? _publishTimer;
  bool _connected = false;
  bool _connecting = false;
  String? _error;
  double _driveX = 0;
  double _driveY = 0;
  double _craneX = 0;
  double _craneY = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publishTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!_connected) return;
      if (_driveX != 0 || _driveY != 0) _publishDrive();
      if (_craneX != 0 || _craneY != 0) _publishCrane();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAll(sendZeros: true);
    }
  }

  Future<void> _connect() async {
    if (_connecting || _connected) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final client = MqttServerClient.withPort(_host, _deviceId, _port);
    client
      ..secure = true
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 10000
      ..logging(on: false)
      ..onConnected = () {
        if (!mounted) return;
        setState(() {
          _connected = true;
          _connecting = false;
          _error = null;
        });
      }
      ..onDisconnected = () {
        if (!mounted) return;
        setState(() {
          _connected = false;
          _connecting = false;
        });
      };
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_deviceId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client = client;

    try {
      final status = await client.connect();
      if (status?.state == MqttConnectionState.connected) {
        if (mounted) {
          setState(() {
            _connected = true;
            _connecting = false;
          });
        }
      } else {
        client.disconnect();
        if (mounted) {
          setState(() {
            _connected = false;
            _connecting = false;
            _error = 'اتصال برقرار نشد؛ وضعیت بروکر را بررسی کنید.';
          });
        }
      }
    } catch (e) {
      client.disconnect();
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _error = 'خطای اتصال: $e';
        });
      }
    }
  }

  Future<void> _disconnect() async {
    _stopAll(sendZeros: true);
    final client = _client;
    _client = null;
    client?.disconnect();
    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
      });
    }
  }

  void _stopAll({required bool sendZeros}) {
    if (sendZeros) {
      _publishDriveValues(0, 0);
      _publishCraneValues(0, 0);
    }
    _driveX = 0;
    _driveY = 0;
    _craneX = 0;
    _craneY = 0;
    if (mounted) setState(() {});
  }

  void _publish(String topic, String payload) {
    final client = _client;
    if (!_connected || client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    final data = builder.payload;
    if (data != null) {
      client.publishMessage(topic, MqttQos.atMostOnce, data);
    }
  }

  int _bounded(int value) => value.clamp(-255, 255).toInt();

  void _publishDriveValues(double x, double y) {
    // Up is forward; right stick deflection turns right. Differential mix:
    // left = throttle + turn, right = throttle - turn, independently clamped.
    final throttle = y * 255;
    final turn = x * 255;
    final left = _bounded((throttle + turn).round());
    final right = _bounded((throttle - turn).round());
    _publish(_driveTopic, jsonEncode({'left': left, 'right': right}));
  }

  void _publishCraneValues(double x, double y) {
    final lift = _bounded((y * 255).round());
    final rotate = _bounded((x * 255).round());
    _publish(_craneTopic, jsonEncode({'lift': lift, 'rotate': rotate}));
  }

  void _publishDrive() => _publishDriveValues(_driveX, _driveY);
  void _publishCrane() => _publishCraneValues(_craneX, _craneY);

  void _updateDrive(double x, double y) {
    _driveX = x;
    _driveY = y;
    _publishDrive();
  }

  void _endDrive() {
    _driveX = 0;
    _driveY = 0;
    _publishDriveValues(0, 0);
  }

  void _updateCrane(double x, double y) {
    _craneX = x;
    _craneY = y;
    _publishCrane();
  }

  void _endCrane() {
    _craneX = 0;
    _craneY = 0;
    _publishCraneValues(0, 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _publishTimer?.cancel();
    // Best effort safety zeros before closing the network connection.
    _publishDriveValues(0, 0);
    _publishCraneValues(0, 0);
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _JoystickPanel(
                        title: 'حرکت خودرو',
                        subtitle: 'بالا/پایین: جلو و عقب  •  چپ/راست: گردش',
                        icon: Icons.directions_car_filled,
                        onChanged: _updateDrive,
                        onReleased: _endDrive,
                        axisX: 'گردش',
                        axisY: 'جلو / عقب',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _JoystickPanel(
                        title: 'جرثقیل',
                        subtitle: 'بالا/پایین: بالابر  •  چپ/راست: چرخش',
                        icon: Icons.precision_manufacturing,
                        onChanged: _updateCrane,
                        onReleased: _endCrane,
                        axisX: 'چرخش',
                        axisY: 'بالابر',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final statusColor = _connected
        ? const Color(0xFF35D07F)
        : (_connecting ? const Color(0xFFFFC857) : const Color(0xFFFF6673));
    return Row(
      children: [
        const Icon(Icons.settings_remote, color: Color(0xFF17C9B5), size: 25),
        const SizedBox(width: 8),
        const Text('کنترل جرثقیل',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2731),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(_connected
                  ? 'متصل • $_host:$_port'
                  : (_connecting ? 'در حال اتصال…' : 'قطع • $_host:$_port')),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF8992), fontSize: 11)),
          ),
        ] else
          const Spacer(),
        OutlinedButton.icon(
          onPressed: _connecting ? null : (_connected ? _disconnect : _connect),
          icon: Icon(_connected ? Icons.link_off : Icons.link),
          label: Text(_connected ? 'قطع اتصال' : 'اتصال'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB8323C),
            foregroundColor: Colors.white,
          ),
          onPressed: () => _stopAll(sendZeros: true),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('توقف اضطراری'),
        ),
      ],
    );
  }
}

class _JoystickPanel extends StatelessWidget {
  const _JoystickPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
    required this.onReleased,
    required this.axisX,
    required this.axisY,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final void Function(double x, double y) onChanged;
  final VoidCallback onReleased;
  final String axisX;
  final String axisY;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF17232D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273844)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF17C9B5), size: 20),
              const SizedBox(width: 7),
              Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Flexible(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 10, color: Colors.white60)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(constraints.maxWidth, constraints.maxHeight);
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: _TouchJoystick(
                      onChanged: onChanged,
                      onReleased: onReleased,
                    ),
                  ),
                );
              },
            ),
          ),
          Text('$axisY  ↑↓     $axisX  ←→',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _TouchJoystick extends StatefulWidget {
  const _TouchJoystick({required this.onChanged, required this.onReleased});

  final void Function(double x, double y) onChanged;
  final VoidCallback onReleased;

  @override
  State<_TouchJoystick> createState() => _TouchJoystickState();
}

class _TouchJoystickState extends State<_TouchJoystick> {
  int? _activePointer;
  double _x = 0;
  double _y = 0;

  void _handleDown(PointerDownEvent event) {
    // Accept one pointer only; ignore extra fingers to avoid accidental jumps.
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _updateFromPosition(event.localPosition);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _updateFromPosition(event.localPosition);
  }

  void _updateFromPosition(Offset position) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final radius = math.min(size.width, size.height) * 0.38;
    if (radius <= 0) return;
    var x = (position.dx - size.width / 2) / radius;
    var y = (size.height / 2 - position.dy) / radius;
    final magnitude = math.sqrt(x * x + y * y);
    if (magnitude > 1) {
      x /= magnitude;
      y /= magnitude;
    }
    setState(() {
      _x = x;
      _y = y;
    });
    widget.onChanged(x, y);
  }

  void _finish(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    setState(() {
      _x = 0;
      _y = 0;
    });
    widget.onReleased();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: (event) => _finish(event.pointer),
      onPointerCancel: (event) => _finish(event.pointer),
      child: CustomPaint(
        painter: _JoystickPainter(x: _x, y: _y),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  const _JoystickPainter({required this.x, required this.y});
  final double x;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.43;
    final base = Paint()..color = const Color(0xFF202F3A);
    final outline = Paint()
      ..color = const Color(0xFF3B515F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, base);
    canvas.drawCircle(center, radius, outline);
    final guide = Paint()
      ..color = const Color(0xFF415461)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), guide);
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), guide);
    canvas.drawCircle(center, radius * 0.52, outline);

    final travel = radius * 0.62;
    final knobCenter = Offset(center.dx + x * travel, center.dy - y * travel);
    canvas.drawCircle(
      knobCenter.translate(0, 3),
      radius * 0.28,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    final knobPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF32E0CB), Color(0xFF079B91)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: knobCenter, radius: radius * 0.27));
    canvas.drawCircle(knobCenter, radius * 0.27, knobPaint);
    canvas.drawCircle(
      knobCenter,
      radius * 0.27,
      Paint()
        ..color = const Color(0xFF8AFFF0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      oldDelegate.x != x || oldDelegate.y != y;
}