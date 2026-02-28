//
//  SettingsTabView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    Toggle("Example Setting", isOn: .constant(true))
                    Toggle("Another Setting", isOn: .constant(false))
                }
            }
            .navigationTitle("Settings")
        }
    }
}
