//
//  SelectionState.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import Foundation
import Combine

enum StudioSelection: Hashable {
    case device(UUID)
    case connection(UUID)
}

@MainActor
final class SelectionState: ObservableObject {
    @Published var selection: StudioSelection? = nil
}
