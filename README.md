# Health Wearable
Support programs for a fully autonomous Bluetooth pedometer. Firmware (.ino) uploaded to Arduino Nano RP2040 with a TensorFlow Lite model to count steps and connect to a mobile app (.swift) through Bluetooth.

## Process
We started off with test firmware built on Arduino IDE and uploaded to an Arduino Nano RP2040 to count steps with a timed loop. We then trained and tested a TensorFlow Lite model to decide whether accelerometer data constituted walking or stationary states. After numerous tests, we uploaded the model to our board (Nano RP2040) with a custom program to take the classification and count one step per arm movement.

To make the product user-accessible, we developed a custom Bluetooth app (based on LightBlue) to connect to our wearable and display the detected step count live. The mobile app is built in Swift and runs on all iOS devices.

The actual physical product consists of an adjustable wristband that includes the board, accelerometer, and battery, all seamlessly connected and stashed in a hidden pouch.

Pics will be added soon!
