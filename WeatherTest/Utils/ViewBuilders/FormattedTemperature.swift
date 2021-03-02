//
//  FormattedTemperature.swift
//  WeatherTest
//
//  Created by user on 2/22/21.
//

import SwiftUI

struct FormattedTemperature: View {
    var temperature: Double
    var unit: Temperature
    
    @ViewBuilder var body: some View {
        switch unit {
        case Temperature.fahrenheit:
            Text(String(format: "%.0f°F", kelvinToFarenheit(temperature)))
        case Temperature.celsius:
             Text(String(format: "%.0f°C", kelvinToCelsius(temperature)))
        default:
            Text(String(format: "%.0f°K", temperature))
        }
        
    }
}

func kelvinToFarenheit(_ kelvin: Double) -> Double {
    return kelvin * 1.8 - 459.67
}

func kelvinToCelsius(_ celsius: Double) -> Double {
    return celsius - 273.15
}
