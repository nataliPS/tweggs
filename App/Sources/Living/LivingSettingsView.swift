import SwiftUI

/// Settings for the living world. Everything is opt-in and stays on this device.
struct LivingSettingsView: View {
    @Environment(GameModel.self) private var model
    @State private var cityQuery = ""
    @State private var cityError = false
    @State private var busy = false
    #if DEBUG
    @State private var forcedWeather: SimulatedWeather? = SimulatedWeatherOverride.current
    #endif

    var body: some View {
        Form {
            Section {
                Toggle("Real weather", isOn: Binding(get: { model.living.weatherEnabled },
                                                     set: { model.setWeatherEnabled($0) }))
                if model.living.weatherEnabled, WeatherProviders.currentKind == .apple {
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
                }
                if model.living.weatherEnabled, let w = model.weather {
                    Label { Text(w.current.title) } icon: { Image(systemName: w.current.systemImage) }
                }
            } header: {
                Text("Weather")
            } footer: {
                Text("Your Mixling reacts to rain, heat, snow and wind. Location is approximate (city level), used only to look up the weather and never stored on our servers. Without it, weather stays neutral.")
            }

            #if DEBUG
            if WeatherProviders.currentKind == .simulated {
                Section {
                    Picker(selection: $forcedWeather) {
                        Text(verbatim: "Daily pattern").tag(SimulatedWeather?.none)
                        ForEach(SimulatedWeather.allCases) { w in
                            Text(verbatim: w.rawValue.capitalized).tag(SimulatedWeather?.some(w))
                        }
                    } label: {
                        Text(verbatim: "Force weather")
                    }
                    .onChange(of: forcedWeather) { _, value in
                        SimulatedWeatherOverride.set(value)
                        Task { await model.refreshWeather(force: true) }
                    }
                } header: {
                    Text(verbatim: "Developer: simulated weather")
                } footer: {
                    Text(verbatim: "DEBUG only. WeatherKit is off (no TWEGGS_WEATHERKIT flag). Turn on Real weather above to see it.")
                }
            }
            #endif

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

            Section {
                Toggle(isOn: Binding(get: { model.save.wellbeing.windDownEnabled },
                                     set: { model.setWindDownEnabled($0) })) {
                    Text(verbatim: WellbeingContent.shared.text("winddown.toggle"))
                }
            } header: {
                Text(verbatim: WellbeingContent.shared.text("winddown.title"))
            } footer: {
                Text(verbatim: WellbeingContent.shared.text("winddown.toggleFooter"))
            }

            Section {
                HardTimeButton()
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
