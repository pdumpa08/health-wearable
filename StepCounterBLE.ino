/*
  Step Counter over BLE (based on ArduinoBLE > Peripheral > LED)

  Board  = Peripheral | GATT server (advertises + holds the data)
  Phone  = Central    | GATT client (LightBlue / nRF Connect)

  The step count lives in ONE characteristic inside ONE custom service.
  The characteristic is Read + Notify, so the phone can subscribe once
  and get every new value pushed to it (notify > polling).
*/

#include <ArduinoBLE.h>

// ---- GATT structure (declarations) ----
// Custom 128-bit UUIDs. Ideally generate your own (any online UUID generator).
// Same pattern as the LED example: service ends ...0, characteristic ends ...1
BLEService stepService("19B10010-E8F2-537E-4F6C-D104768A1214");

BLEUnsignedIntCharacteristic stepCharacteristic(
  "19B10011-E8F2-537E-4F6C-D104768A1214",
  BLERead | BLENotify);

// ---- Week 1 looper variable ----
// Swap this for the variable you made in week 1 (same name/type if you like).
unsigned int stepCount = 0;

unsigned long lastUpdate = 0;
const unsigned long UPDATE_MS = 500;   // how often the count goes up

void setup() {
  Serial.begin(9600);
  // The LED example has while (!Serial); here. Leave it out so the sketch
  // still runs when the board isn't plugged into the Serial Monitor.

  if (!BLE.begin()) {
    Serial.println("starting Bluetooth Low Energy module failed!");
    while (1);
  }

  // ---- GAP + GATT setup ----
  BLE.setLocalName("StepCounter");        // the name scanners show
  BLE.setAdvertisedService(stepService);  // put the service UUID in the ad

  stepService.addCharacteristic(stepCharacteristic);
  BLE.addService(stepService);

  stepCharacteristic.writeValue(stepCount);  // initial value

  BLE.advertise();                        // start broadcasting on 37/38/39
  Serial.println("BLE Step Counter advertising...");
}

void loop() {
  // Wait for a central (the phone) to connect
  BLEDevice central = BLE.central();

  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());

    while (central.connected()) {
      updateSteps();
    }

    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }

  // Keep counting even when nothing is connected
  updateSteps();
}

// Loops forever: bump the count and push it out over BLE
void updateSteps() {
  if (millis() - lastUpdate >= UPDATE_MS) {
    lastUpdate = millis();
    stepCount++;
    stepCharacteristic.writeValue(stepCount);  // notifies subscribed phones
    Serial.print("Steps: ");
    Serial.println(stepCount);
  }
}
