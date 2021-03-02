//
//  ChartCV.swift
//  WeatherTest
//
//  Created by user on 2/24/21.
//

import Charts
import SwiftUI

struct ChartCV: View {
    
    var forecast: Response!
    
    @State private var state = 1
    @State private var barEntries: [BarChartDataEntry] = []
    
    var body: some View {
        VStack {
            Picker(selection: $state, label: Text(""), content: {
                Text("Линейный".localized).tag(1)
                Text("Cтолбцовый".localized).tag(2)
            })
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            if state == 1 {
                LineChart(entries: dataEntriesForWeek(forecast.daily))
            } else if state == 2 {
                BarChart(entries: dataEntriesForWeek(forecast.daily))
            }
        }
        .navigationBarTitle("Ежедневный прогноз")
        .onAppear {
            print(forecast.daily.count)
        }
    }
    
    func dataEntriesForWeek(_ dailyForecast: [DailyForecast]) -> [BarChartDataEntry] {
        let week = [0, 1, 2, 3, 4, 5, 6, 7]
        var daily: [BarChartDataEntry] = []
        for day in 0...7 {
            daily.append(BarChartDataEntry(x: Double(week[day]), y: kelvinToCelsius(dailyForecast[day].temp.day)))
        }
        return daily
    }
}

struct ChartCV_Previews: PreviewProvider {
    static var previews: some View {
        ChartCV()
    }
}
