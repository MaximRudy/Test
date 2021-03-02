//
//  HistoryWeatherRow.swift
//  WeatherTest
//
//  Created by user on 1/25/21.
//

import SwiftUI

struct HistoryWeatherRow: View {
    
    let weatherForecast: WeatherHistory?
    var tempUnit: Temperature = .celsius
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                weatherForecast?.cityName.map(Text.init)
                    .font(.title)
            }
            Spacer()
            FormattedTemperature(temperature: weatherForecast?.feelsLikeTemp ?? 0, unit: tempUnit)
                .font(.title)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                weatherForecast?.date.map { Text(DateFormatter.timeFormatter.string(from: $0)) }
                    .font(.caption)
                Spacer()
                weatherForecast?.date.map { Text(DateFormatter.dateFormatter.string(from: $0)) }
                    .font(.caption)
            }
        }
    }
}
