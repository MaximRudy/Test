//
//  SettingsCV.swift
//  WeatherTest
//
//  Created by user on 2/21/21.
//

import SwiftUI

struct SettingsCV: View {
    
    @ObservedObject var viewModel: MainViewModel
    
    @State var modeApp: Bool = false
    
    var body: some View {
        ZStack {
            VStack {
                VStack {
                    HStack {
                        Text("Temperature".localized)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    Picker(selection: $viewModel.temperature, label: Text("Temperature".localized), content: {
                        Text("Fahrenheit".localized + "°F").tag(Temperature.fahrenheit)
                        Text("Celsius".localized + "°C").tag(Temperature.celsius)
                        Text("Kelvin".localized + "°K").tag(Temperature.kelvin)
                    })
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.top, 20)
                VStack {
                    HStack {
                        Text("Wind Speed".localized)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    Picker(selection: $viewModel.speed, label: Text("Speed".localized), content: {
                        Text("mph".localized).tag(Speed.mph)
                        Text("km/h".localized).tag(Speed.kmh)
                        Text("m/s".localized).tag(Speed.mps)
                    })
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.top, 20)
                
                VStack {
                    NavigationLink(destination: HistoryWeatherCV()) {
                        HStack {
                            Image(systemName: "book")
                                .foregroundColor(.primary)
                            Text("History".localized)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    NavigationLink(destination: SearchCV(locationSearchService: LocationSearchService())) {
                        HStack {
                            Image(systemName: "function")
                                .foregroundColor(.primary)
                            Text("Charts".localized)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.primary)
                        Text("Dark mode".localized)
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: $modeApp)
                            .onTapGesture {
                                self.modeApp.toggle()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
                .padding(.top, 50)
                
                Spacer()
            }
            .padding([.leading, .trailing], 16)
        }
        .navigationBarTitle("Settings", displayMode: .inline)
    }
}

struct SettingsCV_Previews: PreviewProvider {
    static var previews: some View {
        SettingsCV(viewModel: MainViewModel(weatherFetcher: DataManager()))
    }
}
