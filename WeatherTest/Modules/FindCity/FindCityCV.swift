//
//  ContentView.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//

import SwiftUI

struct FindCityCV: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    
    @ObservedObject var viewModel: FindCityViewModel
    
    var body: some View {
        ZStack {
            
            RoundedRectangle(cornerRadius: 15.0)
                .fill(LinearGradient(
                        gradient: Gradient(colors: gradients[MainDaypart.mid] ?? [Color.white]),
                        startPoint: UnitPoint(x: 0.5, y: 0.2),
                        endPoint: UnitPoint(x: 0.5, y: 0.5)))
                .shadow(color: Color(#colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.25)), radius: 10, x: 0, y: 4)
            
            GeometryReader { _ in
                VStack(alignment: .center, spacing: 0) {
                    
                    Spacer()
                    
                    Image("weather_icon")
                        .resizable()
                        .frame(width: 150.0, height: 150.0)
                    
                    Text("Enter the name of the city".localized)
                        .font(.system(size: 25, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    SkyFloatingContentView(city: self.$viewModel.searchCity, activeButton: self.$viewModel.activeButton)
                        .frame(height: 45)
                    
                    NavigationLink(destination:
                                    WeatherInfoCV(viewModel: WeatherInfoViewModel(toWeatherInfoCV: .fromFindCityCV, weather: self.viewModel.weather), isUpdate: .constant(false)),
                                   isActive: self.$viewModel.showingDetailView) { EmptyView() }
                    
                    showWeatherButton
                        .padding(.vertical, 16)
                    
                    Spacer()
                    
                    showHistoryButton
                        .padding(.bottom, 16)
                    
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
            .alert(isPresented: self.$viewModel.showingAlert) {
                Alert(title: Text("Warning".localized), message: Text("Please check grammar".localized), dismissButton: .default(Text("Got it!".localized)))
            }
        }
        .onTapGesture {
            UIApplication.shared.endEditing()
        }
        .padding(10)
    }
}

extension FindCityCV {
    var showWeatherButton: some View {
        Button(action: {
            UIApplication.shared.endEditing()
            if self.viewModel.activeButton {
                // self.viewModel.fetchWeather(forCity: self.viewModel.searchCity)
                self.viewModel.fetchWithAF(forCity: self.viewModel.searchCity)
                // addWeatherHistory()
            } else {
                self.viewModel.showingAlert = true
            }
        }) {
            HStack {
                Spacer()
                Text("Show weather".localized)
                    .foregroundColor(.white)
                    .padding()
                Spacer()
            }
            .background(Color(#colorLiteral(red: 0.4004163146, green: 0.5982140899, blue: 0.999102056, alpha: 1)))
            .cornerRadius(16)
            .shadow(radius: 3)
        }
    }
    
    var showHistoryButton: some View {
        NavigationLink(destination: HistoryWeatherCV().environment(\.managedObjectContext, self.managedObjectContext)) {
            HStack {
                Spacer()
                Text("Show history".localized)
                    .foregroundColor(.white)
                    .padding()
                Spacer()
            }
            .background(Color(#colorLiteral(red: 0.4004163146, green: 0.5982140899, blue: 0.999102056, alpha: 1)))
            .cornerRadius(12)
            .shadow(radius: 3)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        FindCityCV(viewModel: .init(weatherFetcher: DataManager()))
    }
}
