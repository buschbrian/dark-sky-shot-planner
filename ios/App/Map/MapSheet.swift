import SwiftUI

/// The map's panel as a bottom sheet over a full-screen map (review B-6 a).
/// Three detents: the peek (always shown), half and full. Drag the peek, or
/// tap or adjust the grabber, to move it. Drawn in-view rather than as a
/// system sheet, so the tab bar (or field dock) stays usable and the sheet
/// takes the palette in field mode.
enum MapSheetDetent: String, CaseIterable {
    case peek, half, full

    var spoken: String {
        switch self {
        case .peek: "collapsed"
        case .half: "half height"
        case .full: "full height"
        }
    }
}

struct MapSheet<Peek: View, Content: View>: View {
    typealias Detent = MapSheetDetent

    @Binding var detent: Detent
    /// Height of the collapsed sheet, measured from the peek; the map keeps its content clear of it.
    @Binding var peekHeight: CGFloat
    /// From under the navigation bar to the tab bar.
    let available: CGFloat
    @ViewBuilder var peek: Peek
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette
    @GestureState private var drag: CGFloat = 0

    static func height(_ d: Detent, peek: CGFloat, available: CGFloat) -> CGFloat {
        switch d {
        case .peek: min(peek, available)
        case .half: min(available, max(peek + 120, available * 0.5))
        case .full: available
        }
    }

    var body: some View {
        let rest = Self.height(detent, peek: peekHeight, available: available)
        let h = min(available, max(min(peekHeight, available), rest - drag))
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                grabber
                peek
            }
            // Its ideal height, whatever the sheet's current height: measuring a
            // squeezed peek would shrink the next frame's sheet in a loop.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { peekHeight = $0.rounded(.up) }
            .contentShape(Rectangle())
            .gesture(dragGesture(rest: rest))
            Rectangle().fill(palette.hairline).frame(height: 1)
            ScrollView {
                content
                    .padding(.horizontal, DS.Space.screen)
                    .padding(.top, DS.Space.m)
                    .padding(.bottom, DS.Space.xl)
            }
            .scrollDisabled(detent == .peek)
            .accessibilityHidden(detent == .peek)
        }
        .frame(maxWidth: .infinity)
        .frame(height: h, alignment: .top)
        .clipped()
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.card, topTrailingRadius: DS.Radius.card, style: .continuous)
                .fill(palette.background)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: DS.Radius.card, topTrailingRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: DS.Stroke.hairline))
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.sheet")
    }

    private var grabber: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                detent = switch detent {
                case .peek: .half
                case .half: .full
                case .full: .peek
                }
            }
        } label: {
            Capsule().fill(palette.tertiary)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel("Map panel")
        .accessibilityValue(detent.spoken)
        .accessibilityHint("Shows more or less of the panel below the map")
        .accessibilityAdjustableAction { direction in
            let all = Detent.allCases
            let i = all.firstIndex(of: detent) ?? 0
            let next = direction == .increment ? min(all.count - 1, i + 1) : max(0, i - 1)
            withAnimation(.snappy(duration: 0.25)) { detent = all[next] }
        }
        .accessibilityIdentifier("map.sheet.grabber")
    }

    private func dragGesture(rest: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($drag) { v, state, _ in state = v.translation.height }
            .onEnded { v in
                let projected = rest - v.predictedEndTranslation.height
                let nearest = Detent.allCases.min {
                    abs(Self.height($0, peek: peekHeight, available: available) - projected)
                        < abs(Self.height($1, peek: peekHeight, available: available) - projected)
                } ?? detent
                withAnimation(.snappy(duration: 0.25)) { detent = nearest }
            }
    }
}
