import SwiftUI

struct RollingCounter: View {
    let value: Int
    let font: Font
    let color: Color

    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(countsDown: false))
            .animation(value == 0 ? nil : .spring(duration: 0.35), value: value)
    }
}
