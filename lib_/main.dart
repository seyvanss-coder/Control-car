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
  runApp(const CraneRemoteApp());
}

class CraneRemoteApp extends StatelessWidget {
  const CraneRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CraneControllerScreen(),
    );
  }
}

class CraneControllerScreen extends StatefulWidget {
  const CraneControllerScreen({super.key});

  @override
  State<CraneControllerScreen> createState() => _CraneControllerScreenState();
}

class _CraneControllerScreenState extends State<CraneControllerScreen> {
  MqttServerClient? client;
  bool isConnected = false;
  final String deviceId = 'car1';

  // متد ارسال دستور با ایمنی بیشتر (برای توقف خودکار)
  void send(String cmd, String val) {
    if (isConnected && client != null) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(val);
      client!.publishMessage('cranecar/$deviceId/cmd/$cmd', MqttQos.atMostOnce, builder.payload!);
    }
  }

  void connectMQTT() async {
    // ... منطق اتصال شما (بدون تغییر خاص)
    setState(() => isConnected = !isConnected); // تست دکمه
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // رنگ بدنه کنترلر واقعی
      body: Row(
        children: [
          // بخش چپ: حرکت (D-Pad)
          Expanded(child: _buildLeftControls()),
          
          // بخش وسط: نمایشگر/وضعیت
          _buildCenterStatus(),
          
          // بخش راست: جرثقیل (Action Buttons)
          Expanded(child: _buildRightControls()),
        ],
      ),
    );
  }

  Widget _buildLeftControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlButton(Icons.keyboard_arrow_up, 'y', '100'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _controlButton(Icons.keyboard_arrow_left, 'x', '-100'),
            const SizedBox(width: 20),
            _controlButton(Icons.keyboard_arrow_right, 'x', '100'),
          ],
        ),
        _controlButton(Icons.keyboard_arrow_down, 'y', '-100'),
      ],
    );
  }

  Widget _buildRightControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionButton("UP", Colors.green, 'c', '100'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _actionButton("ROT", Colors.blue, 'r', '-100'),
            const SizedBox(width: 20),
            _actionButton("ROT", Colors.blue, 'r', '100'),
          ],
        ),
        _actionButton("DWN", Colors.red, 'c', '-100'),
      ],
    );
  }

  // ویجت دکمه‌ها با ظاهر نئومورفیک
  Widget _controlButton(IconData icon, String cmd, String val) {
    return GestureDetector(
      onTapDown: (_) => send(cmd, val),
      onTapUp: (_) => send(cmd, '0'),
      onTapCancel: () => send(cmd, '0'),
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _actionButton(String text, Color color, String cmd, String val) {
    return GestureDetector(
      onTapDown: (_) => send(cmd, val),
      onTapUp: (_) => send(cmd, '0'),
      onTapCancel: () => send(cmd, '0'),
      child: Container(
        margin: const EdgeInsets.all(8),
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Center(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _buildCenterStatus() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: connectMQTT,
          icon: Icon(isConnected ? Icons.link : Icons.link_off, color: isConnected ? Colors.green : Colors.grey, size: 40),
        ),
        Text(isConnected ? "CONNECTED" : "DISCONNECTED", style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }
}
