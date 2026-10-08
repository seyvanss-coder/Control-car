import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const PS5RemoteApp());
}

class PS5RemoteApp extends StatelessWidget {
  const PS5RemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PS5ControllerScreen(),
    );
  }
}

class PS5ControllerScreen extends StatefulWidget {
  const PS5ControllerScreen({super.key});

  @override
  State<PS5ControllerScreen> createState() => _PS5ControllerScreenState();
}

class _PS5ControllerScreenState extends State<PS5ControllerScreen> {
  MqttServerClient? client;
  bool isConnected = false;
  final String deviceId = 'car1';

  void connectMQTT() async {
    client = MqttServerClient('broker.hivemq.com', 'ps5_${DateTime.now().millisecondsSinceEpoch}');
    client!.secure = true;
    client!.port = 8883;
    client!.loggingOn = false;
    try {
      await client!.connect();
      setState(() => isConnected = true);
    } catch (e) {
      setState(() => isConnected = false);
    }
  }

  void send(String cmd, String val) {
    if (isConnected && client != null) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(val);
      client!.publishMessage('cranecar/$deviceId/cmd/$cmd', MqttQos.atMostOnce, builder.payload!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1015),
      body: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F8),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withOpacity(0.2),
                  blurRadius: 25,
                  spreadRadius: 5,
                )
              ],
            ),
            child: Stack(
              children: [
                // Top Touchpad Area (PS5 Style)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 220,
                    height: 85,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E212B),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25), top: Radius.circular(10)),
                      border: Border.all(
                        color: isConnected ? Colors.cyanAccent : Colors.grey.shade700,
                        width: 2,
                      ),
                      boxShadow: isConnected
                          ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 10)]
                          : [],
                    ),
                    child: InkWell(
                      onTap: connectMQTT,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isConnected ? Icons.wifi : Icons.wifi_off,
                            color: isConnected ? Colors.cyanAccent : Colors.white54,
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isConnected ? "PS5 ONLINE (car1)" : "TAP TO CONNECT",
                            style: TextStyle(
                              color: isConnected ? Colors.cyanAccent : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Left D-Pad
                Positioned(
                  left: 35,
                  top: 45,
                  child: Column(
                    children: [
                      _dpadBtn(Icons.arrow_drop_up, 'y', '100'),
                      Row(
                        children: [
                          _dpadBtn(Icons.arrow_left, 'x', '-100'),
                          const SizedBox(width: 35),
                          _dpadBtn(Icons.arrow_right, 'x', '100'),
                        ],
                      ),
                      _dpadBtn(Icons.arrow_drop_down, 'y', '-100'),
                    ],
                  ),
                ),

                // Right PS Action Buttons
                Positioned(
                  right: 35,
                  top: 45,
                  child: Column(
                    children: [
                      _actionBtn('▲', Colors.greenAccent, 'c', '100'),
                      Row(
                        children: [
                          _actionBtn('■', Colors.pinkAccent, 'r', '-100'),
                          const SizedBox(width: 35),
                          _actionBtn('●', Colors.redAccent, 'r', '100'),
                        ],
                      ),
                      _actionBtn('✖', Colors.lightBlueAccent, 'c', '-100'),
                    ],
                  ),
                ),

                // Left Stick
                Positioned(
                  bottom: 20,
                  left: 170,
                  child: _analogStick("DRIVE"),
                ),

                // Right Stick
                Positioned(
                  bottom: 20,
                  right: 170,
                  child: _analogStick("CRANE"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dpadBtn(IconData icon, String cmd, String val) {
    return GestureDetector(
      onTapDown: (_) => send(cmd, val),
      onTapUp: (_) => send(cmd, '0'),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF2B303C),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 3))],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, String cmd, String val) {
    return GestureDetector(
      onTapDown: (_) => send(cmd, val),
      onTapUp: (_) => send(cmd, '0'),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF2B303C),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 3))],
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _analogStick(String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 75,
          height: 75,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF434A59), Color(0xFF1B1E26)],
            ),
            border: Border.all(color: Colors.grey.shade400, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: const Center(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF111317),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF333D4B)),
        ),
      ],
    );
  }
}
