//
//  LiquidGlassComponents.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import SwiftUI

struct LiquidPanel<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color = .white.opacity(0.18)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .glassEffect(.regular.tint(tint).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ToolButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        if prominent {
            Button(action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var label: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .frame(height: 30)
    }
}

struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

struct PressablePlainButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
