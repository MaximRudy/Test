//
//  MainViewModel.swift
//  WeatherTest
//
//  Created by user on 2/17/21.
//

import Combine
import SwiftUI
import CoreLocation

final class MainViewModel: ObservableObject {
    
    @Published var weather: Response?
    
    @Published var temperature: Temperature {
        didSet {
            UserDefaults.standard.set(temperature.rawValue, forKey: "temperature")
        }
    }
    
    @Published var speed: Speed {
        didSet {
            UserDefaults.standard.set(speed.rawValue, forKey: "speed")
        }
    }
    
    @Published var showFindCityCV = false
    @Published var isloading = false
    @Published var showingAlert = false
    
    private var disposable = Set<AnyCancellable>()
    
    private var weatherFetcher: DataManager
    
    init(weatherFetcher: DataManager) {
        self.weatherFetcher = weatherFetcher
        self.temperature = (UserDefaults.standard.object(forKey: "temperature") == nil ?
                                Temperature.fahrenheit :
                                Temperature(rawValue: UserDefaults.standard.object(forKey: "temperature") as! Int)) ?? Temperature.celsius
        self.speed = (UserDefaults.standard.object(forKey: "speed") == nil ? Speed.mph : Speed(rawValue: UserDefaults.standard.object(forKey: "speed") as! Int)) ?? Speed.kmh
    }
    
    // MARK: - Request for coordinates
    func fetchWeather(location: CLLocation?) {
        
        guard let latitude = location?.coordinate.latitude else { return }
        guard let longitude = location?.coordinate.longitude else { return }
        
        weatherFetcher.currentWeatherForecast(latitude: latitude, longitude: longitude)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (value) in
                switch value {
                case .failure(let error):
                    self?.weather = nil
                    self?.isloading = false
                    print(error)
                case .finished:
                    break
                }
            }) { [weak self] weather in
                self?.weather = weather
                self?.isloading = false
            }.store(in: &disposable)
    }
}
