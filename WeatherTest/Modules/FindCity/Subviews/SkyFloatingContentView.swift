//
//  SkyFloatingContentView.swift
//  WeatherTest
//
//  Created by user on 1/19/21.
//

import SkyFloatingLabelTextField
import SwiftUI

struct SkyFloatingContentView: UIViewRepresentable {
    
    @Binding var city: String
    @Binding var activeButton: Bool
    
    class Coordinator: NSObject, UITextFieldDelegate {
        
        var parent: SkyFloatingContentView
        
        private lazy var regex = "^[a-zA-Zа-яА-Я- .]{2,}$"
        
        init(_ parent: SkyFloatingContentView) {
            self.parent = parent
        }
        
        private func checkCity(_ textField: SkyFloatingLabelTextField) {
            
            guard let text = textField.text else { return }
            guard text.count != 0 else { return textField.errorMessage = "" }
            
            if !text.matches(regex) {
                textField.errorMessage = "Invalid name".localized
                self.parent.activeButton = false
            } else {
                textField.errorMessage = ""
                self.parent.city = text
                self.parent.activeButton = true
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard let floatingLabelTextField = textField as? SkyFloatingLabelTextField else { return }
            checkCity(floatingLabelTextField)
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
        
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SkyFloatingLabelTextField {
        return SkyFloatingLabelTextField(frame: CGRect(x: 10, y: 10, width: 200, height: 45))
    }

    func updateUIView(_ textField: SkyFloatingLabelTextField, context: Context) {
        textField.tintColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        textField.textColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        textField.placeholder = "City".localized
        textField.title = "City".localized
        textField.delegate = context.coordinator
    }

}
