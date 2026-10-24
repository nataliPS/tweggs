import SwiftUI

/// Settings for the living world. Everything is opt-in and stays on this device.
struct LivingSettingsView: View {
    @Environment(GameModel.self) private var model
    @State private var cityQuery = ""
    @State private var cityError = false
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Toggle("Real weather", isOn: Binding(get: { model.living.weatherEnabled },
                                                     set: { model.setWeatherEnabled($0) }))
                if model.living.weatherEnabled {
                    Toggle("Use my approximate location", isOn: Binding(
                        get: { model.living.useLocation },
                        set: { on in Task { await model.setUseLocation(on) } }))
                    if !model.living.useLocation {
                        HStack {
                            TextField("City", text: $cityQuery)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit(lookUp)
                            Button("Set", action: lookUp).disabled(busy || cityQuery.isEmpty)
                        }
                        if let city = model.living.manualCity {
                            HStack {
                                Label { Text(verbatim: city.name) } icon: { Image(systemName: "mappin.and.ellipse") }
                                Spacer()
                                Button("Remove", role: .destructive) { Task { await model.setManualCity(nil) } }
                            }
                        }
                        if cityError {
                            Text("City not found. Try another spelling.")
                                .font(Theme.caption(12))
                                .foregroundStyle(Theme.mood)
                        }
                    }
                    if let w = model.weather {
                        Label { Text(w.current.title) } icon: { Image(systemName: w.current.systemImage) }
                    }
                }
            } header: {
                Text("Weather")
            } footer: {
                Text("Your Mixling reacts to rain, heat, snow and wind. Location is approximate (city level), used only to look up the weather and never stored on our servers. Without it, weather stays neutral.")
            }

            Section {
                Toggle("Gentle reminders", isOn: Binding(get: { model.living.nudgesEnabled },
                                                         set: { on in Task { await model.setNudgesEnabled(on) } }))
            } footer: {
                Text("At most 2 friendly notifications a day, like a sip of water or a stretch. Never at night.")
            }

            if LineService.aiAvailable {
                Section {
                    Text("Lines written by on-device AI")
                } footer: {
                    Text("Some lines are written by Apple's on-device model. Only your Mixling's name, temper and the weather type are used. Nothing leaves your device.")
                }
            }

            Section {
                WeatherAttributionView()
            }
        }
        .navigationTitle("Living world")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lookUp() {
        let q = cityQuery
        busy = true
        cityError = false
        Task {
            let city = await LivingWeatherService.shared.lookUpCity(q)
            if let city {
                await model.setManualCity(city)
                cityQuery = ""
            } else {
                cityError = true
            }
            busy = false
        }
    }
}
