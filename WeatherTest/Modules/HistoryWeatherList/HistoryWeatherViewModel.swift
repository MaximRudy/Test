//
//  HistoryWeatherViewModel.swift
//  WeatherTest
//
//  Created by user on 1/29/21.
//

import Combine
import SwiftUI
import CoreData

final class HistoryWeatherViewModel: ObservableObject {
    
    @Published var weatherHistory: [WeatherHistory] = []
    @Published var filteredHistory: [WeatherHistory] = []
    
    @Published var isUpdate = false
    
    @Published var state = 1 {
        didSet {
            if state == 1 {
                self.filteredHistory = weatherHistory
            } else if state == 2 {
                self.filteredHistory = weatherHistory.filter {($0.date?.isInToday ?? false)}
            } else if state == 3 {
                self.filteredHistory = weatherHistory.filter {($0.date?.isInThisWeek ?? false)}
            }
        }
    }
    
    init() {
        self.loadWeatherHistiry()
    }
    
    func loadWeatherHistiry() {
        DispatchQueue.main.async {
            self.weatherHistory = CoreDataManager.shared.getWeatherHistory()
            self.filteredHistory = self.weatherHistory
        }
    }
    
    func deleteWeatherHistiry(at offsets: IndexSet) {
        offsets.forEach { index in
            let weatherHistory = self.filteredHistory[index]
            do {
                try CoreDataManager.shared.deleteWeatherHistory(weatherHistory: weatherHistory)
            } catch {
                print(error.localizedDescription)
            }
        }
        loadWeatherHistiry()
    }
    
}
