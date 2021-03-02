//
//  HistoryWeatherCV.swift
//  WeatherTest
//
//  Created by user on 1/25/21.
//

import SwiftUI

struct HistoryWeatherCV: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    
    @ObservedObject var viewModel = HistoryWeatherViewModel()
    
    var body: some View {
        List {
            Picker(selection: $viewModel.state, label: Text(""), content: {
                Text("Вся".localized).tag(1)
                Text("Сегодня".localized).tag(2)
                Text("На этой неделе".localized).tag(3)
            })
            .pickerStyle(SegmentedPickerStyle())
            
            ForEach(viewModel.filteredHistory, id: \.id) { weather in
                NavigationLink(destination: WeatherInfoCV(viewModel: WeatherInfoViewModel(toWeatherInfoCV: .fromHistoryWeatherCV,
                                                                                          weatherFromHistory: weather),
                                                          isUpdate: $viewModel.isUpdate)) {
                    HistoryWeatherRow(weatherForecast: weather)
                }
            }
            .onDelete(perform: self.viewModel.deleteWeatherHistiry)
        }
        .navigationBarTitle(Text("History".localized))
        .onReceive(self.viewModel.$isUpdate) { isUpdate in
            if isUpdate {
                self.viewModel.loadWeatherHistiry()
                self.viewModel.isUpdate.toggle()
            }
        }
    }
}

struct HistoryWeatherList_Previews: PreviewProvider {
    static var previews: some View {
        HistoryWeatherCV()
    }
}
