import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RealisticPS5CraneScreen(),
  ));
}

class RealisticPS5CraneScreen extends StatefulWidget {
  const RealisticPS5CraneScreen({super.key});

  @override
  State<RealisticPS5CraneScreen> createState() => _RealisticPS5CraneScreenState();
}

class _RealisticPS5CraneScreenState extends State<RealisticPS5CraneScreen>
    with WidgetsBindingObserver {
  static const String _broker = 'broker.hivemq.com';
  static const int _port = 8883;
  static const String _deviceId = 'car1';
  static const List<String> _commands = <String>[
    'forward', 'backward', 'left', 'right', 'up', 'down', 'rot_left', 'rot_right',
  ];

  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _connectionGeneration = 0;
  // هر pointer مالک یک فرمان؛ چند انگشت روی یک دکمه، صفر را زودهنگام نمی‌فرستند.
  final Map<int, String> _activePointers = <int, String>{};
  final Map<String, Set<int>> _commandPointers = <String, Set<int>>{};
  static const Map<String, String> _opposites = <String, String>{
    'forward': 'backward', 'backward': 'forward', 'left': 'right', 'right': 'left',
    'up': 'down', 'down': 'up', 'rot_left': 'rot_right', 'rot_right': 'rot_left',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _canPublish =>
      mounted &&
      _isConnected &&
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  void _updateState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Future<void> _toggleConnection() async {
    if (_isConnecting) {
      // لغو منطقی تلاش؛ callbackهای تلاش قدیمی با generation بی‌اعتبار می‌شوند.
      ++_connectionGeneration;
      final oldClient = _client;
      _client = null;
      _updateState(() {
        _isConnecting = false;
        _isConnected = false;
      });
      try {
        oldClient?.disconnect();
      } catch (_) {}
      _releasePressedLocally();
      return;
    }

    if (_isConnected) {
      await _disconnectByUser();
      return;
    }
    await _connect();
  }

  Future<void> _connect() async {
    final int generation = ++_connectionGeneration;
    final String clientId =
        'ps5_crane_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';
    final MqttServerClient candidate = MqttServerClient.withPort(
      _broker,
      clientId,
      _port,
    )
      ..secure = true
      ..loggingOn = false
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 10000
      ..autoReconnect = false;

    _client = candidate;
    _updateState(() {
      _isConnecting = true;
      _isConnected = false;
    });

    candidate.onConnected = () {
      if (!mounted || generation != _connectionGeneration || !identical(_client, candidate)) return;
      _updateState(() {
        _isConnected = true;
        _isConnecting = false;
      });
    };
    candidate.onDisconnected = () {
      if (!mounted || generation != _connectionGeneration || !identical(_client, candidate)) return;
      _releasePressedLocally();
      _updateState(() {
        _isConnected = false;
        _isConnecting = false;
      });
    };

    try {
      final MqttClientConnectionStatus? status = await candidate.connect();
      if (!mounted || generation != _connectionGeneration || !identical(_client, candidate)) {
        candidate.disconnect();
        return;
      }
      final bool connected =
          status?.state == MqttConnectionState.connected &&
          candidate.connectionStatus?.state == MqttConnectionState.connected;
      if (!connected) {
        candidate.disconnect();
        _updateState(() {
          _isConnected = false;
          _isConnecting = false;
        });
        _showMessage('اتصال MQTT برقرار نشد. وضعیت: ${status?.state ?? 'نامشخص'}');
      } else {
        _updateState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      }
    } catch (error) {
      if (generation == _connectionGeneration && identical(_client, candidate)) {
        try {
          candidate.disconnect();
        } catch (_) {}
        _client = null;
        _updateState(() {
          _isConnected = false;
          _isConnecting = false;
        });
        _releasePressedLocally();
        _showMessage('خطا در اتصال MQTT: $error');
      }
    }
  }

  Future<void> _disconnectByUser() async {
    final MqttServerClient? oldClient = _client;
    // ابتدا تا وقتی سوکت قابل استفاده است دستور توقف ارسال می‌شود.
    _stopAll(sendWhenConnected: true);
    ++_connectionGeneration;
    _client = null;
    _updateState(() {
      _isConnected = false;
      _isConnecting = false;
    });
    try {
      oldClient?.disconnect();
    } catch (error) {
      _showMessage('خطا هنگام قطع اتصال: $error');
    }
  }

  /// فقط در حالت اتصال واقعی publish می‌کند؛ بعد از قطع هیچ فرمانی صف نمی‌شود.
  bool _send(String command, String value) {
    if (!_commands.contains(command) || !_canPublish) return false;
    final MqttServerClient? current = _client;
    if (current == null) return false;
    try {
      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder()..addString(value);
      final payload = builder.payload;
      if (payload == null || payload.isEmpty) return false;
      // بررسی دوباره درست پیش از publish برای جلوگیری از ارسال روی session منقضی.
      if (!identical(current, _client) || !_canPublish) return false;
      current.publishMessage(
        'cranecar/$_deviceId/cmd/$command',
        MqttQos.atMostOnce,
        payload,
      );
      return true;
    } catch (error) {
      // session معیوب را قبل از قطع invalidate می‌کنیم تا callback قدیمی UI را تغییر ندهد.
      ++_connectionGeneration;
      final MqttServerClient? failedClient = _client;
      _client = null;
      _releasePressedLocally();
      _updateState(() {
        _isConnected = false;
        _isConnecting = false;
      });
      try {
        failedClient?.disconnect();
      } catch (_) {}
      _showMessage('ارسال فرمان ناموفق بود: $error');
      return false;
    }
  }

  bool _press(String command, int pointer) {
    if (!_commands.contains(command) || _activePointers.containsKey(pointer)) return false;
    final Set<int>? owners = _commandPointers[command];
    if (owners == null) {
      // از صدور دو جهت مخالف برای یک محور هم‌زمان جلوگیری می‌شود.
      if (_commandPointers.containsKey(_opposites[command])) return false;
      if (!_send(command, '1')) return false;
      _commandPointers[command] = <int>{pointer};
      HapticFeedback.lightImpact();
    } else {
      owners.add(pointer);
    }
    _activePointers[pointer] = command;
    return true;
  }

  void _releasePointer(int pointer) {
    final String? command = _activePointers.remove(pointer);
    if (command == null) return;
    final Set<int>? owners = _commandPointers[command];
    if (owners == null) return;
    owners.remove(pointer);
    if (owners.isEmpty) {
      _commandPointers.remove(command);
      _send(command, '0');
    }
  }

  void _releasePressedLocally() {
    // در قطع اتصال، صفر قابل ارسال نیست؛ مالکیت pointerها نیز باید پاک شود.
    _activePointers.clear();
    _commandPointers.clear();
  }

  void _stopAll({bool sendWhenConnected = true}) {
    _releasePressedLocally();
    if (sendWhenConnected && _canPublish) {
      // همه فرمان‌ها صفر می‌شوند، نه فقط مواردی که UI آن‌ها را pressed ثبت کرده.
      for (final String command in _commands) {
        _send(command, '0');
      }
    }
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            final double height = constraints.maxHeight;
            final double scale = (math.min(width / 700, height / 360)).clamp(0.65, 1.2).toDouble();
            return Center(
              child: SizedBox(
                width: width * 0.98,
                height: height * 0.98,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double w = box.maxWidth;
                    final double h = box.maxHeight;
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CustomPaint(painter: PS5BodyPainter(isConnected: _isConnected)),
                        Align(
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleConnection,
                            child: Container(
                              margin: EdgeInsets.only(top: 8 * scale),
                              width: 200 * scale,
                              height: 80 * scale,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1D24),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(20), top: Radius.circular(8),
                                ),
                                border: Border.all(
                                  color: _isConnected ? Colors.cyanAccent : const Color(0xFF3B404D),
                                  width: 2,
                                ),
                                boxShadow: _isConnected
                                    ? <BoxShadow>[BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 12)]
                                    : const <BoxShadow>[],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(_isConnected ? Icons.power : Icons.power_off,
                                      color: _isConnected ? Colors.cyanAccent : Colors.white38, size: 26 * scale),
                                  SizedBox(height: 4 * scale),
                                  Text(
                                    _isConnected ? 'CONNECTED ($_deviceId)' : _isConnecting ? 'CONNECTING...' : 'TOUCH TO CONNECT',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isConnected ? Colors.cyanAccent : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10 * scale,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 12 * scale,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _stopAll,
                              child: Container(
                                width: 50 * scale,
                                height: 50 * scale,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF14161C),
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 2),
                                  boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 4))],
                                ),
                                child: Center(child: Text('STOP', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 10 * scale))),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: math.max(8.0, w * 0.07).toDouble(),
                          top: 0,
                          bottom: 10 * scale,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text('DRIVE CAR', style: TextStyle(color: Colors.white70, fontSize: 11 * scale, fontWeight: FontWeight.bold)),
                                SizedBox(height: 8 * scale),
                                _dpadBtn(Icons.keyboard_arrow_up, 'forward', 'جلو', scale),
                                Row(children: <Widget>[
                                  _dpadBtn(Icons.keyboard_arrow_left, 'left', 'چپ', scale),
                                  SizedBox(width: 38 * scale),
                                  _dpadBtn(Icons.keyboard_arrow_right, 'right', 'راست', scale),
                                ]),
                                _dpadBtn(Icons.keyboard_arrow_down, 'backward', 'عقب', scale),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: math.max(8.0, w * 0.07).toDouble(),
                          top: 0,
                          bottom: 10 * scale,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text('CRANE', style: TextStyle(color: Colors.amberAccent, fontSize: 11 * scale, fontWeight: FontWeight.bold)),
                                SizedBox(height: 8 * scale),
                                _psActionBtn('▲', Colors.greenAccent, 'up', 'بالا', scale),
                                Row(children: <Widget>[
                                  _psActionBtn('■', Colors.pinkAccent, 'rot_left', 'چپ', scale),
                                  SizedBox(width: 38 * scale),
                                  _psActionBtn('●', Colors.redAccent, 'rot_right', 'راست', scale),
                                ]),
                                _psActionBtn('✖', Colors.lightBlueAccent, 'down', 'پایین', scale),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dpadBtn(IconData icon, String command, String label, double scale) {
    return _HoldCommandButton(
      onPress: (int pointer) => _press(command, pointer),
      onRelease: _releasePointer,
      child: Container(
        margin: EdgeInsets.all(4 * scale),
        width: 48 * scale,
        height: 48 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2E3B),
          borderRadius: BorderRadius.circular(10 * scale),
          border: Border.all(color: const Color(0xFF4A5163)),
          boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 20 * scale),
            Text(label, style: TextStyle(color: Colors.white54, fontSize: 8 * scale)),
          ],
        ),
      ),
    );
  }

  Widget _psActionBtn(String symbol, Color color, String command, String label, double scale) {
    return _HoldCommandButton(
      onPress: (int pointer) => _press(command, pointer),
      onRelease: _releasePointer,
      child: Container(
        margin: EdgeInsets.all(4 * scale),
        width: 48 * scale,
        height: 48 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2A2E3B),
          border: Border.all(color: color.withOpacity(0.8), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withOpacity(0.2), blurRadius: 6),
            const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(symbol, style: TextStyle(color: color, fontSize: 15 * scale, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 8 * scale)),
          ],
        ),
      ),
    );
  }
}

/// دکمهٔ نگه‌داشتنی با مالکیت مستقل برای هر pointer و لغو هنگام خروج از محدوده.
class _HoldCommandButton extends StatefulWidget {
  const _HoldCommandButton({
    required this.onPress,
    required this.onRelease,
    required this.child,
  });

  final bool Function(int pointer) onPress;
  final void Function(int pointer) onRelease;
  final Widget child;

  @override
  State<_HoldCommandButton> createState() => _HoldCommandButtonState();
}

class _HoldCommandButtonState extends State<_HoldCommandButton> {
  final Set<int> _pointers = <int>{};

  void _release(int pointer) {
    if (_pointers.remove(pointer)) widget.onRelease(pointer);
  }

  @override
  void dispose() {
    for (final int pointer in _pointers.toList()) {
      widget.onRelease(pointer);
    }
    _pointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        if (widget.onPress(event.pointer)) _pointers.add(event.pointer);
      },
      onPointerMove: (PointerMoveEvent event) {
        final RenderObject? object = context.findRenderObject();
        if (object is RenderBox && _pointers.contains(event.pointer)) {
          final Offset p = event.localPosition;
          final Rect bounds = Offset.zero & object.size;
          if (!bounds.contains(p)) _release(event.pointer);
        }
      },
      onPointerUp: (PointerUpEvent event) => _release(event.pointer),
      onPointerCancel: (PointerCancelEvent event) => _release(event.pointer),
      child: widget.child,
    );
  }
}

class PS5BodyPainter extends CustomPainter {
  const PS5BodyPainter({required this.isConnected});

  final bool isConnected;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint whitePaint = Paint()..color = const Color(0xFFE5E9F0);
    final Paint darkCenterPaint = Paint()..color = const Color(0xFF14161C);
    final Path body = Path()
      ..moveTo(w * 0.18, 0)
      ..lineTo(w * 0.82, 0)
      ..quadraticBezierTo(w * 0.98, h * 0.15, w * 0.94, h * 0.85)
