//
//  SunDial.swift
//  WeatherTest
//
//  Created by user on 2/8/21.
//

import SwiftUI

struct Arc: Shape {
    let radius: CGFloat
    let startAngle: Angle = .degrees(0)
    let endAngle: Angle = .degrees(180)
    let clockWise: Bool = true
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockWise)
        
        return path
    }
}

struct SunDial: View {
    
    var sunrise: Int
    var sunset: Int
    var timestamp: Int
    var timezone: String
    
    let strokeDash: [CGFloat] = [5, 5]
    
    @State private var targetAngle: Double = 0
    
    // var date = Date(timeIntervalSince1970: Double(1600394388))
    var date: Date { Date(timeIntervalSince1970: Double(timestamp))}
    
    var nextAngle: Double {
        updateTargetAngle(date)
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer()
                    Text("Sun from".localized + " \(formatDateToHoursMinutes(sunrise)) " + "to".localized + " \(formatDateToHoursMinutes(sunset))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        // .padding(.top, 15)
                    Spacer()
                    ZStack(alignment: Alignment(horizontal: .center, vertical: .bottom)) {
                        Arc(radius: geometry.size.width / 2.5)
                            .fill(LinearGradient(
                                    gradient: Gradient(stops: [
                                                        .init(color: Color(#colorLiteral(red: 1, green: 0.892666757106781, blue: 0.6166666746139526, alpha: 1)), location: 0),
                                                        .init(color: Color(#colorLiteral(red: 1, green: 0.6822500228881836, blue: 0.612500011920929, alpha: 0.30000001192092896)), location: 1)]),
                                    startPoint: UnitPoint(x: 0.5, y: 0),
                                    endPoint: UnitPoint(x: 0.5, y: 0.9)))
                            .frame(height: geometry.size.width / 2.5)
                            .opacity(0.7)
                        HStack(spacing: (geometry.size.width / 2.5 - 5) * 2) {
                            VStack {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 10, height: 10)
                            }
                            VStack {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 10, height: 10)
                                
                            }
                        }.padding(.bottom, 0)
                        VStack {
                            if Int(date.timeIntervalSince1970) >= sunrise && Int(date.timeIntervalSince1970) < sunset {
                                Image("sun-mid")
                                    .resizable()
                                    // .rotationEffect(.degrees(-self.targetAngle))
                                    .scaledToFit()
                                    .frame(height: 50)
                                    .position(x: 0, y: 0)
                                    .rotationEffect( .degrees(self.targetAngle))
                                    .animation(Animation.easeInOut(duration: 3 + 3 * self.targetAngle / 180))
                            }
                            
                        }.frame(width: (geometry.size.width / 2.5) * 2, height: 1)
                    }
                }
            }
            .onAppear {
                self.targetAngle = updateTargetAngle(date)
            }
        }.frame(height: UIScreen.main.bounds.height / 3.5)
    }
    
    func updateTargetAngle(_ updatedDate: Date) -> Double {
        return Double((Int(updatedDate.timeIntervalSince1970) - sunrise) * 180 / (sunset - sunrise))
    }
    
    func formatDateToHoursMinutes(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = NSLocale.current
        formatter.timeZone = TimeZone(identifier: timezone)
        var formattedDate: String {formatter.string(from: date)}
        
        return formattedDate
    }
}

struct SunDial_Previews: PreviewProvider {
    static var previews: some View {
        SunDial(sunrise: 1600374388, sunset: 1600418714, timestamp: 1600394388, timezone: "Asia/Tokyo")
    }
}
