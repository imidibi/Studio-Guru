//
//  WelcomeView.swift
//  Studio Guru
//
//  Shown instead of an empty canvas when the user has no studio yet.
//  Examples open in their own window; see ExampleStudioHost.
//

import SwiftUI

struct WelcomeView: View {
    let onSelectExample: (ExampleStudio) -> Void
    let onStartBlank: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Welcome to Studio Guru")
                        .font(.largeTitle.bold())
                    Text("Map your gear and how it's connected. Explore an example to see how it works, then build your own studio.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 480)
                }

                VStack(spacing: 12) {
                    ForEach(ExampleStudio.allCases) { example in
                        Button {
                            onSelectExample(example)
                        } label: {
                            exampleRow(example)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 480)

                Text("Examples open in a separate window. Nothing in them is saved to your studios.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Start with a Blank Studio", action: onStartBlank)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
    }

    private func exampleRow(_ example: ExampleStudio) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(example.title)
                        .font(.headline)
                }
                Text(example.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
