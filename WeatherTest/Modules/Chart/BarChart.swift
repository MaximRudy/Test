//
//  BarChart.swift
//  WeatherTest
//
//  Created by user on 2/24/21.
//

import Charts
import SwiftUI

struct BarChart: UIViewRepresentable {
    
    typealias UIViewType = BarChartView
    
    var entries: [BarChartDataEntry]
    
    func makeUIView(context: Context) -> BarChartView {
        let chart = BarChartView()
        chart.data = addData()
        return chart
    }
    
    func updateUIView(_ uiView: BarChartView, context: Context) {
        uiView.data = addData()
        formatXAxis(xAxis: uiView.xAxis)
    }
    
    func addData() -> BarChartData {
        let data = BarChartData()
        let dataSet = BarChartDataSet(entries: entries)
        dataSet.colors = ChartColorTemplates.material()
        dataSet.label = "Daily Forecast"
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        dataSet.valueFormatter = DefaultValueFormatter(formatter: formatter)
        data.addDataSet(dataSet)
        return data
    }
    
    func formatXAxis(xAxis: XAxis) {
        let date = Date()
        let currentWeekday = Calendar.current.component(.weekday, from: date)
        let week = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var weekForAxis: [String] = ["Today"]
        for day in currentWeekday ... currentWeekday + 6 {
            weekForAxis.append(week[day])
        }
        xAxis.valueFormatter = IndexAxisValueFormatter(values: weekForAxis)
    }
}

struct BarChart_Previews: PreviewProvider {
    static var previews: some View {
        BarChart(entries: [
            BarChartDataEntry(x: 1, y: 1),
            BarChartDataEntry(x: 2, y: 1),
            BarChartDataEntry(x: 3, y: 2),
            BarChartDataEntry(x: 4, y: 1),
            BarChartDataEntry(x: 5, y: 1)
            
        ])
    }
}
