//
//  FormattedSpeed.swift
//  WeatherTest
//
//  Created by user on 2/22/21.
//

import SwiftUI

struct FormattedSpeed: View {
    var speed: Double
    var unit: Speed
    
    @ViewBuilder var body: some View {
        switch unit {
        case Speed.mph:
            Text(String(format: "%.1f " + "mph".localized, metersPerSecToMPH(speed)))
        case Speed.kmh:
            Text(String(format: "%.1f " + "km/h".localized, metersPerSecToKMH(speed)))
        default:
            Text(String(format: "%.1f " + "m/s".localized, speed))
            
        }
    }
}

func metersPerSecToMPH(_ mps: Double) -> Double {
    return mps / 0.44704
}

func metersPerSecToKMH(_ mps: Double) -> Double {
    return mps * 18 / 5
}
