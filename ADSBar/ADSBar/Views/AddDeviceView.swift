import SwiftUI

struct AddDeviceView: View {
    @Bindable var store: FeederStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Add Station")
                    .font(.caption.bold())
                Spacer()
                Button("Cancel") {
                    store.isAddingDevice = false
                    store.newDeviceName = ""
                    store.newDeviceIP = ""
                    store.newDeviceType = .fr24
                    store.newDevicePort = "8754"
                    store.newDeviceSSL = false
                    store.newDeviceWebPath = ""
                    store.newDeviceLat = ""
                    store.newDeviceLon = ""
                }
                .font(.caption)
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
            }

            Picker("Type", selection: $store.newDeviceType) {
                ForEach(StationType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.caption)
            .onChange(of: store.newDeviceType) { _, newType in
                store.newDevicePort = String(newType.defaultPort)
                if newType == .airplanesLive {
                    store.newDeviceIP = "api.airplanes.live"
                    store.newDeviceSSL = true
                } else if store.newDeviceIP == "api.airplanes.live" {
                    store.newDeviceIP = ""
                    store.newDeviceSSL = false
                }
            }

            TextField("Name (e.g. ADS-B Station #1)", text: $store.newDeviceName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if store.newDeviceType != .airplanesLive {
                HStack(spacing: 8) {
                    TextField("Host / IP (e.g. 192.168.1.100)", text: $store.newDeviceIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    TextField("Port", text: $store.newDevicePort)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 60)

                    Toggle("SSL", isOn: $store.newDeviceSSL)
                        .font(.caption)
                }
                .onSubmit { store.addDevice() }

                TextField("Web UI path (e.g. /tar1090/)", text: $store.newDeviceWebPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                TextField("Latitude", text: $store.newDeviceLat)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                TextField("Longitude", text: $store.newDeviceLon)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Button("Add") {
                store.addDevice()
            }
            .disabled(store.newDeviceName.trimmingCharacters(in: .whitespaces).isEmpty ||
                store.newDeviceIP.trimmingCharacters(in: .whitespaces).isEmpty)
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct EditDeviceView: View {
    @Bindable var store: FeederStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Edit Station")
                    .font(.caption.bold())
                Spacer()
                Button("Cancel") { store.cancelEdit() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(.secondary)
            }

            Picker("Type", selection: $store.editType) {
                ForEach(StationType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.caption)
            .onChange(of: store.editType) { _, newType in
                store.editPort = String(newType.defaultPort)
                if newType == .airplanesLive {
                    store.editIP = "api.airplanes.live"
                    store.editSSL = true
                } else if store.editIP == "api.airplanes.live" {
                    store.editIP = ""
                    store.editSSL = false
                }
            }

            TextField("Name", text: $store.editName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if store.editType != .airplanesLive {
                HStack(spacing: 8) {
                    TextField("Host / IP", text: $store.editIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    TextField("Port", text: $store.editPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 60)

                    Toggle("SSL", isOn: $store.editSSL)
                        .font(.caption)
                }
                .onSubmit { store.saveEdit() }

                TextField("Web UI path (e.g. /tar1090/)", text: $store.editWebPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                TextField("Latitude", text: $store.editLat)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                TextField("Longitude", text: $store.editLon)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Button("Save") {
                store.saveEdit()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
