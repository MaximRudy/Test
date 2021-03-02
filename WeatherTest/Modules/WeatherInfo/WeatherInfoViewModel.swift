//
//  WeatherInfoViewModel.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//

import Foundation
import Combine

final class WeatherInfoViewModel: ObservableObject {
   
    @Published var navigationTitle: String = ""
    @Published var currentTemp: String = ""
    @Published var feelsLikeTemp: String = ""
    @Published var city: String = ""
    @Published var base: String = ""
    @Published var time: String = ""
    @Published var date: String = ""
    @Published var weatherFromHistory: WeatherHistory?
    @Published var isUpdate = false
    @Published var isPresented = false
    
    private var weatherFetcher = DataManager()
    private var disposable = Set<AnyCancellable>()
    private var weather: WeatherResponse?
    var weatherHistory: [WeatherHistory] = []
    
    var toWeatherInfoCV: ToWeatherInfoCV
    
    private func configuration(weather: WeatherResponse?) {
        guard let navigationTitle = weather?.name else { return }
        guard let currentTemp = weather?.main?.temp else { return }
        guard let feelsLikeTemp = weather?.main?.feelsLike else { return }
        guard let name = weather?.name else { return }
        guard let base = weather?.weather?[0].weatherDescription else { return }
        
        self.navigationTitle = navigationTitle
        self.currentTemp = "Temperature".localized + ": " + String(format: "%.0f°", currentTemp - 273.15)
        self.feelsLikeTemp = "Feels like".localized + ": " + String(format: "%.0f°", feelsLikeTemp - 273.15)
        self.city = "City".localized + ": " + name
        self.base = "Description".localized + ": " + base
    }
    
    private func configuration(weather: WeatherHistory?) {
        guard let navigationTitle = weather?.cityName else { return }
        guard let currentTemp = weather?.currentTemp else { return }
        guard let feelsLikeTemp = weather?.feelsLikeTemp else { return }
        guard let name = weather?.cityName else { return }
        guard let base = weather?.discription else { return }
        guard let date = weather?.date else { return }
        
        self.navigationTitle = navigationTitle
        self.currentTemp = "Temperature".localized + ": " + String(format: "%.0f°", currentTemp - 273.15)
        self.feelsLikeTemp = "Feels like".localized + ": " + String(format: "%.0f°", feelsLikeTemp - 273.15)
        self.city = "City".localized + ": " + name
        self.base = "Description".localized + ": " + base
        self.date = "Date".localized + ": " + DateFormatter.dateFormatter.string(from: date)
        self.time = "Time".localized + ": " + DateFormatter.timeFormatter.string(from: date)
    }
    
    init(toWeatherInfoCV: ToWeatherInfoCV, weatherFromHistory: WeatherHistory?) {
        self.toWeatherInfoCV = toWeatherInfoCV
        self.weatherFromHistory = weatherFromHistory
        self.configuration(weather: weatherFromHistory)
        self.loadWeatherHistiry(city: weatherFromHistory?.cityName ?? "")
    }
    
    init(toWeatherInfoCV: ToWeatherInfoCV, weather: WeatherResponse?) {
        self.toWeatherInfoCV = toWeatherInfoCV
        self.weather = weather
        self.configuration(weather: weather)
    }
    
    // MARK: - Request for update city
    func updateWeather() {
        weatherFetcher.currentWeatherForecast(for: weatherFromHistory?.cityName ?? "")
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (value) in
                switch value {
                case .failure(let error):
                    self?.weather = nil
                    print(error)
                case .finished:
                    break
                }
            }) { [weak self] weather in
                self?.update(newWeather: weather)
            }.store(in: &disposable)
    }
    
    func update(newWeather: WeatherResponse) {
        do {
            try CoreDataManager.shared.updateWeatherHistory(weatherHistoryId: weatherFromHistory?.id ?? UUID(), weather: newWeather)
            try self.weatherFromHistory = CoreDataManager.shared.getByWeatherHistoryId(weatherHistoryId: weatherFromHistory?.id ?? UUID()) ?? WeatherHistory()
            self.configuration(weather: self.weatherFromHistory)
            self.isUpdate = true
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func loadWeatherHistiry(city: String) {
        DispatchQueue.main.async {
            self.weatherHistory = CoreDataManager.shared.getWeatherHistoryCity(city: city)
        }
    }
}
