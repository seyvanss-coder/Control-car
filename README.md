Flutter MQTT remote controller — Wemos firmware interface

Connection
- Broker: broker.hivemq.com
- Secure MQTT/TLS TCP port: 8883 (client identifier: car1; keepalive: 20 seconds)
- This app uses mqtt_client and publishes QoS 0, non-retained messages.

Exact command topics and JSON examples
- Topic: cranecar/car1/cmd/drive
  Example payload: {"left":180,"right":120}
  Stop payload:    {"left":0,"right":0}
- Topic: cranecar/car1/cmd/crane
  Example payload: {"lift":200,"rotate":-80}
  Stop payload:    {"lift":0,"rotate":0}

All values are integers in the inclusive range -255..255. The drive stick's
vertical axis is throttle (up = forward, down = reverse), and its horizontal
axis is steering (right = turn right). Differential mixing is left = throttle
+ steering and right = throttle - steering, with each motor value clamped
independently to -255..255. Thus forward with right-turn input speeds the left
side more and slows/reverses the right side. The crane stick maps vertical
(up positive) to lift and horizontal (right positive) to rotate. Firmware may
invert motor polarity if its wiring uses opposite directions.

The app sends updated commands while dragging and repeats nonzero joystick
commands every 150 ms. Releasing/cancelling a stick, emergency stop, disconnect,
or app pause sends zero commands (when connected). Each joystick accepts a
single active pointer and ignores other fingers.