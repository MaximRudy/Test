//
//  DailyForecast.swift
//  WeatherTest
//
//  Created by user on 2/23/21.
//

import Foundation

struct DailyForecast: Hashable, Decodable {
    static func == (lhs: DailyForecast, rhs: DailyForecast) -> Bool {
        return lhs.dt > rhs.dt
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dt)
    }
    
    let dt: Int
    let sunrise: Int
    let sunset: Int
    let temp: DetailTemp
    let feelsLike: DetailFeelsLikeTemp
    let pressure: Int
    let humidity: Int
    let dewPoint: Double
    let windSpeed: Double
    let windDeg: Int
    let weather: [WeatherObject]
    let clouds: Int
}
