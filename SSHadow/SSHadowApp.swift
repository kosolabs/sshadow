//
//  SSHadowApp.swift
//  SSHadow
//
//  Created by Shad Sharma on 1/21/26.
//

import SwiftUI

@main
struct SSHadowApp: App {
    init() {
        print("hi")
    }
    var body: some Scene {
        WindowGroup {
            ConnectionConfigView()
        }
    }
}
