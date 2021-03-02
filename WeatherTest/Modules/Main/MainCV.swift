//
//  MainCV.swift
//  WeatherTest
//
//  Created by user on 2/15/21.
//

import SwiftUI

struct MainCV: View {
    
    @ObservedObject var viewModel = MainViewModel(weatherFetcher: DataManager())
    @ObservedObject var locationManager = LocationManager()
    
    var body: some View {
        LoadingView(isShowing: self.$viewModel.isloading) {
            NavigationView {
                ZStack {
                    VStack {
                        TopBar(viewModel: self.viewModel)
                        if self.viewModel.showFindCityCV {
                            FindCityCV(viewModel: FindCityViewModel(weatherFetcher: DataManager()))
                        } else {
                            if self.viewModel.weather != nil {
                                WeatherCard(cityName: locationManager.placemark?.locality, forecast: self.viewModel.weather)
                            } else if locationManager.status == .restricted || locationManager.status == .denied {
                                FindCityCV(viewModel: FindCityViewModel(weatherFetcher: DataManager()))
                            }
                        }
                        Spacer()
                        if self.viewModel.showFindCityCV {
                            HStack(alignment: .center, spacing: 0) {
                                Text("Показать текущую погоду ".localized)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                Button(action: {
                                    self.checkLocationStatus()
                                }) {
                                    HStack(alignment: .center) {
                                        Text("в вашем городе".localized)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Color(#colorLiteral(red: 0.4004163146, green: 0.5982140899, blue: 0.999102056, alpha: 1)))
                                    }
                                }.padding(.trailing, 5)
                                Image(systemName: "location")
                                    .foregroundColor(.primary)
                            }.padding(.bottom, 10)
                        }
                    }
                }
                .navigationBarHidden(true)
            }
            .accentColor(.primary)
        }
        .onReceive(self.locationManager.objectWillChange) {
            self.viewModel.isloading = true
            self.viewModel.fetchWeather(location: self.locationManager.location)
           // self.locationManager.stopUpdate()
        }
        .alert(isPresented: self.$viewModel.showingAlert) {
            Alert(title: Text("Allow Weather to access your location while you are using the app?".localized),
                      primaryButton: .default (Text("Allow".localized)) {
                        self.settingsAction()
                      },
                      secondaryButton: .cancel(Text("Don't Allow".localized))
                  )
        }
    }
    
    func settingsAction() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl, completionHandler: nil)
        }
    }
    func checkLocationStatus() {
        switch locationManager.status {
        case .authorizedAlways, .authorizedWhenInUse:
            self.viewModel.showFindCityCV.toggle()
        case .notDetermined, .restricted, .denied:
            self.viewModel.showingAlert = true
        default:
            break
        }
    }
}

struct MainCV_Previews: PreviewProvider {
    static var previews: some View {
        MainCV()
    }
}

