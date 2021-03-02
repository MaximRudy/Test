//
//  City.swift
//  WeatherTest
//
//  Created by user on 1/26/21.
//

import Foundation

struct City: Identifiable {
    var id = UUID()
    var timestamp = Date()
    var lastRefresh = Date()

    let locality: String
    let province: String
    let country: String

    // var weatherData: WeatherResponse

}
