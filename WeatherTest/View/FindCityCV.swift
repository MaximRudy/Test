//
//  ContentView.swift
//  WeatherTest
//
//  Created by user on 12/21/20.
//

import SwiftUI
import SkyFloatingLabelTextField

struct FindCityCV: View {
    
    @ObservedObject var viewModel = FindCityViewModel()
    
    var body: some View {
        NavigationView {

            VStack() {
                
                Text("Введите название города")
                    .fontWeight(.bold)
                    .font(.title)
                    .fixedSize()
                    //.background(Color.black)
                
                SkyFloatingContentView()
                    .frame(height: 45)
                    //.background(Color.black)
                
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("Показать погоду")
                            .foregroundColor(.black)
                            .fontWeight(.bold)
                            .padding()
                        Spacer()
                    }
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(16)
                }
                .padding(.vertical, 16)
                
            }.padding(.horizontal, 32)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        FindCityCV()
    }
}

struct SkyFloatingContentView: UIViewRepresentable {
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SkyFloatingContentView

        init(_ parent: SkyFloatingContentView) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            if let text = textField.text {
                if let floatingLabelTextField = textField as? SkyFloatingLabelTextField {
                    if (text.count < 3) {
                        floatingLabelTextField.errorMessage = "Неверное название"
                    } else {
                        // The error message will only disappear when we reset it to nil or empty string
                        floatingLabelTextField.errorMessage = ""
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SkyFloatingLabelTextField {
        return SkyFloatingLabelTextField(frame: CGRect(x: 10, y: 10, width: 200, height: 45))
    }

    func updateUIView(_ textField: SkyFloatingLabelTextField, context: Context) {
        textField.placeholder = "Город"
        //textField.title = "Your full name"
        textField.delegate = context.coordinator
    }
}
