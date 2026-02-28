//
//  ContentView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ReadTabView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Read", systemImage: "book")
                }
                .tag(0)

            BooksTabView()
                .tabItem {
                    Label("Books", systemImage: "books.vertical")
                }
                .tag(1)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
