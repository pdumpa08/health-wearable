import SwiftUI
import CoreBluetooth

struct ScanAndConnectView: View {
    @State private var ble = BLEManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    Text(ble.bluetoothStatus)
                    LabeledContent("Connection", value: ble.connectionState.rawValue.capitalized)
                    if let name = ble.connectedName { Text(name).font(.headline) }
                    if let error = ble.lastError {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack {
                        Button(ble.connectionState == .scanning ? "Stop Scan" : "Scan") {
                            if ble.connectionState == .scanning { ble.stopScanning() }
                            else { ble.startScanning() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ble.bluetoothState != .poweredOn ||
                                  ![ConnectionState.idle, .scanning].contains(ble.connectionState))

                        if ble.connectionState == .connecting || ble.connectionState == .connected {
                            Button(ble.connectionState == .connecting ? "Cancel" : "Disconnect") {
                                ble.disconnect()
                            }.buttonStyle(.bordered)
                        }
                    }
                    if ble.connectionState == .scanning {
                        Text("Scanning for 15 seconds. Tap a peripheral to connect.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if ble.connectionState == .idle || ble.connectionState == .scanning {
                    Section("Discovered peripherals") {
                        if ble.discoveredPeripherals.isEmpty {
                            Text("Tap Scan with your board powered on and advertising BLE.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(ble.discoveredPeripherals) { device in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(device.name).font(.headline)
                                Text(device.id.uuidString).font(.caption).textSelection(.enabled)
                                Text(device.rssi == 127 ? "RSSI unavailable" : "RSSI: \(device.rssi) dBm")
                                    .font(.caption)
                                if !device.advertisedServices.isEmpty {
                                    Text("Advertised: " + device.advertisedServices.joined(separator: ", "))
                                        .font(.caption).textSelection(.enabled)
                                }
                                Button(device.isConnectable == false ? "Not connectable" : "Connect") {
                                    ble.connect(to: device)
                                }
                                .buttonStyle(.bordered)
                                .disabled(device.isConnectable == false || ble.bluetoothState != .poweredOn)
                            }.padding(.vertical, 4)
                        }
                    }
                }

                if ble.connectionState == .connected {
                    if ble.isDiscoveringServices {
                        Section { ProgressView("Discovering services") }
                    } else if ble.services.isEmpty {
                        Section { Text("No services found. Check the board firmware or the error above.") }
                    }
                    ForEach(ble.services) { service in
                        Section {
                            if service.isDiscovering { ProgressView("Discovering characteristics") }
                            if let error = service.error { Text(error).foregroundStyle(.red) }
                            if !service.isDiscovering && service.error == nil && service.characteristics.isEmpty {
                                Text("No characteristics found").foregroundStyle(.secondary)
                            }
                            ForEach(service.characteristics) { item in
                                CharacteristicRow(item: item,
                                                  onRead: { ble.read(item.id) },
                                                  onSubscribe: { ble.toggleSubscription(item.id) })
                            }
                        } header: {
                            VStack(alignment: .leading) {
                                if let name = service.name { Text(name) }
                                Text("Service: \(service.uuid)")
                            }.textSelection(.enabled)
                        }
                    }
                }

                Section {
                    DisclosureGroup("Activity log") {
                        ForEach(Array(ble.events.enumerated()), id: \.offset) { _, event in
                            Text(event).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("BLE Browser")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { ble.stopScanning() }
        }
    }
}

private struct CharacteristicRow: View {
    let item: CharacteristicInfo
    let onRead: () -> Void
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Characteristic: \(item.uuid)").font(.headline).textSelection(.enabled)
            Text(item.propertyNames.isEmpty ? "No standard properties" : item.propertyNames)
                .font(.caption).foregroundStyle(.secondary)
            Text("Hex: \(item.hexValue)").font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            if let decimal = item.decimalValue {
                Text("Decimal: \(decimal)").font(.caption).textSelection(.enabled)
            }
            if let text = item.textValue {
                Text("UTF-8: \(text.isEmpty ? "(empty text)" : text)")
                    .font(.caption).textSelection(.enabled)
            } else if item.value != nil {
                Text("Value is not valid UTF-8").font(.caption).foregroundStyle(.secondary)
            }
            if let error = item.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if item.canRead {
                    Button(item.readPending ? "Reading…" : "Read", action: onRead)
                        .buttonStyle(.bordered).disabled(item.readPending)
                }
                if item.canSubscribe {
                    Button(item.subscriptionPending ? "Updating…" :
                           (item.isNotifying ? "Unsubscribe" : "Subscribe"), action: onSubscribe)
                        .buttonStyle(.bordered).disabled(item.subscriptionPending)
                }
            }
            if item.canSubscribe {
                Text(item.isNotifying ? "Live updates enabled" : "Live updates disabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
