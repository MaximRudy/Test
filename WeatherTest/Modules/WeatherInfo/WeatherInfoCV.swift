//
//  WeatherInfoCV.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//

import SwiftUI

struct WeatherInfoCV: View {
    
    @ObservedObject var viewModel: WeatherInfoViewModel
    
    @Binding var isUpdate: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                
                RadialGradient(gradient: Gradient(colors: [.blue, .black]), center: .center, startRadius: 2, endRadius: 650).edgesIgnoringSafeArea(.all)
                
                VStack(alignment: .center, spacing: 16) {
                    
                    Text("Weather".localized)
                        .font(.title)
                        .foregroundColor(.white)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(viewModel.city)
                            Text(viewModel.base)
                            Text(viewModel.currentTemp)
                            Text(viewModel.feelsLikeTemp)
                            if self.viewModel.toWeatherInfoCV == .fromHistoryWeatherCV {
                                Text(viewModel.date)
                                Text(viewModel.time)
                                Spacer()
                                updateWeatherButton
                                if self.viewModel.weatherHistory.count > 1 {
                                    showHistoryButton
                                }
                            }
                        }
                            .font(.system(size: 21, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
            }
        }
        .navigationBarTitle("\(viewModel.navigationTitle)", displayMode: .inline)
        .onDisappear {
            self.isUpdate = self.viewModel.isUpdate
        }
    }
}

extension WeatherInfoCV {
    var updateWeatherButton: some View {
        Button(action: {
            self.viewModel.updateWeather()
        }) {
            HStack {
                Spacer()
                Text("Update".localized)
                    .foregroundColor(.white)
                    .padding()
                Spacer()
            }
            .background(Color(#colorLiteral(red: 0.4004163146, green: 0.5982140899, blue: 0.999102056, alpha: 1)))
            .cornerRadius(16)
            .shadow(radius: 3)
        }
    }
    
    var showHistoryButton: some View {
        Button(action: {
            
        }) {
            NavigationLink(destination: historyWeatherCity.navigationBarHidden(true)) {
                HStack {
                    Spacer()
                    Text("History".localized)
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                }
                .background(Color(#colorLiteral(red: 0.4004163146, green: 0.5982140899, blue: 0.999102056, alpha: 1)))
                .cornerRadius(16)
                .shadow(radius: 3)
            }
        }
    }
}

extension WeatherInfoCV {
    var historyWeatherCity: some View {
        List {
            ForEach(self.viewModel.weatherHistory, id: \.id) { weather in
                HistoryWeatherRow(weatherForecast: weather)
            }
        }
    }
}
