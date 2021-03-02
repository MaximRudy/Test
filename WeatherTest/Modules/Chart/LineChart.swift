//
//  LineChart.swift
//  WeatherTest
//
//  Created by user on 2/19/21.
//
import Charts
import SwiftUI

struct LineChart: UIViewRepresentable {
    
    typealias UIViewType = LineChartView
    
    var entries: [BarChartDataEntry]
    
    func makeUIView(context: Context) -> LineChartView {
        let chart = LineChartView()
        chart.data = addData()
        return chart
    }
    
    func updateUIView(_ uiView: LineChartView, context: Context) {
        uiView.data = addData()
        formatXAxis(xAxis: uiView.xAxis)
    }
    
    func addData() -> LineChartData {
        let data = LineChartData()
        let dataSet = LineChartDataSet(entries: entries)
        dataSet.colors = [NSUIColor.green]
        dataSet.label = "Daily Forecast"
        dataSet.mode = .horizontalBezier
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

struct Chart_Previews: PreviewProvider {
    static var previews: some View {
        LineChart(entries: [
            BarChartDataEntry(x: 1, y: 1),
            BarChartDataEntry(x: 2, y: 1),
            BarChartDataEntry(x: 3, y: 2),
            BarChartDataEntry(x: 4, y: 1),
            BarChartDataEntry(x: 5, y: 1)
            
        ])
    }
}
