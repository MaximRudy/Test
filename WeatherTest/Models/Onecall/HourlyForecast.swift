//
//  HourlyForecast.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct HourlyForecast: Hashable, Decodable {
    
    static func == (lhs: HourlyForecast, rhs: HourlyForecast) -> Bool {
        return lhs.dt > rhs.dt
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dt)
    }
    
    let dt: Int
    let temp: Double
    let feelsLike: Double
    let pressure: Int
    let humidity: Int
    let dewPoint: Double
    let clouds: Int
    let visibility: Int
    let windSpeed: Double
    let weather: [WeatherObject]
}
