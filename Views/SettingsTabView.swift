//
//  SettingsTabView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI

struct SettingsTabView: View {
    @AppStorage("wpm") private var wpm: Double = 400
    @AppStorage("holdToPlay") private var holdToPlay: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Reading")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Words per minute")
                            Spacer()
                            Text("\(Int(wpm))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $wpm, in: 100...900, step: 10)
                    }

                    Toggle("Hold to play", isOn: $holdToPlay)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
