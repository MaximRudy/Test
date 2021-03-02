//
//  CoreDataManager.swift
//  WeatherTest
//
//  Created by user on 1/29/21.
//

import Foundation
import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager(managedObjectContext: NSManagedObjectContext.current)
    
    var managedObjectContext: NSManagedObjectContext
    
    private init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    private func save() throws {
        try self.managedObjectContext.save()
    }
    
    func deleteWeatherHistory(weatherHistory: WeatherHistory) throws {
        self.managedObjectContext.delete(weatherHistory)
        try save()
    }
    
    func addToWeatherHistory(weather: WeatherResponse?) throws {

        let newWeatherHistory = WeatherHistory(context: managedObjectContext)
        
        newWeatherHistory.id = UUID()
        newWeatherHistory.cityName = weather?.name
        newWeatherHistory.date = Date()
        newWeatherHistory.discription = weather?.weather?[0].weatherDescription
        newWeatherHistory.currentTemp = weather?.main?.temp ?? 0
        newWeatherHistory.feelsLikeTemp = weather?.main?.feelsLike ?? 0
        
        try save()
    }
    
    func getByWeatherHistoryId(weatherHistoryId: UUID) throws -> WeatherHistory? {
        
        let request: NSFetchRequest<WeatherHistory> = WeatherHistory.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", (weatherHistoryId.uuidString))
        
        let results = try self.managedObjectContext.fetch(request)
        return results.first
    }
    
    func updateWeatherHistory(weatherHistoryId: UUID, weather: WeatherResponse?) throws {

        let newWeatherHistory = try getByWeatherHistoryId(weatherHistoryId: weatherHistoryId)

        if let newWeatherHistory = newWeatherHistory {
            newWeatherHistory.id = UUID()
            newWeatherHistory.cityName = weather?.name
            newWeatherHistory.date = Date()
            newWeatherHistory.discription = weather?.weather?[0].weatherDescription
            newWeatherHistory.currentTemp = weather?.main?.temp ?? 0
            newWeatherHistory.feelsLikeTemp = weather?.main?.feelsLike ?? 0
            try save()
        }
    }
    
    func getWeatherHistory() -> [WeatherHistory] {
        
        var weatherHistory = [WeatherHistory]()
        
        let request: NSFetchRequest<WeatherHistory> = WeatherHistory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        do {
            weatherHistory = try self.managedObjectContext.fetch(request)
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        
        return weatherHistory
    }
    
    func getWeatherHistoryCity(city: String) -> [WeatherHistory] {
        
        var weatherHistory = [WeatherHistory]()
        
        let request: NSFetchRequest<WeatherHistory> = WeatherHistory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.predicate = NSPredicate(format: "cityName == %@", city)
        
        do {
            weatherHistory = try self.managedObjectContext.fetch(request)
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        return weatherHistory
    }
}
