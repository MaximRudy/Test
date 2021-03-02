//
//  FindCityViewModel.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//

import Combine
import SwiftUI
import CoreData

final class FindCityViewModel: ObservableObject {
    
    // Varibals for URLSession request
    private var weatherFetcher: DataManager
    private var disposable = Set<AnyCancellable>()
    
    @Published var weather: WeatherResponse?
    @Published var searchCity: String = ""
    @Published var activeButton: Bool = false
    @Published var showingAlert: Bool = false
    @Published var showingDetailView: Bool = false
    @Published var isPresentedHistory: Bool = false
    
    init(weatherFetcher: DataManager) {
        self.weatherFetcher = weatherFetcher
    }
    
    // MARK: - Request for city
    func fetchWeather(forCity city: String) {
        weatherFetcher.currentWeatherForecast(for: city)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] (value) in
                switch value {
                case .failure(let error):
                    self?.weather = nil
                    self?.showingDetailView = false
                    self?.showingAlert = true
                    print(error)
                case .finished:
                    break
                }
            }) { [weak self] weather in
                self?.weather = weather
                self?.addToHistiry()
                self?.showingDetailView = true
            }.store(in: &disposable)
    }
    
    // MARK: - Request with city(Alamofire)
    func fetchWithAF(forCity city: String) {
        
        weatherFetcher.getWeatherAF(for: city)
            .sink(receiveCompletion: { [weak self](completion) in
                switch completion {
                case .failure(let error):
                    self?.weather = nil
                    self?.showingDetailView = false
                    self?.showingAlert = true
                    print(error.localizedDescription)
                case .finished:
                    break
                }
            }, receiveValue: { [weak self](model) in
                self?.weather = model
                self?.addToHistiry()
                self?.showingDetailView = true
            }).store(in: &disposable)
    }
    
    // MARK: - CoreData
    func addToHistiry() {
        do {
            try CoreDataManager.shared.addToWeatherHistory(weather: weather)
        } catch {
            print(error.localizedDescription)
        }
    }
    
}
