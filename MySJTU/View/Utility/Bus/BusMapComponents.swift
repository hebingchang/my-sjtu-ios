//
//  BusMapComponents.swift
//  MySJTU
//

import SwiftUI

// MARK: - Shared Styles

struct BusRouteStyle {
    let tint: Color

    static let campusShuttle = BusRouteStyle(tint: Color(hex: "1677FF"))
}

struct BusLineShield: View {
    let title: String
    let style: BusRouteStyle
    let prominent: Bool

    var body: some View {
        Text(title)
            .font(.system(size: prominent ? 11 : 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, prominent ? 9 : 8)
            .padding(.vertical, prominent ? 4.5 : 4)
            .background(style.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct BusBubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Loading States

struct BusStationLoadOverlay: View {
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView("正在加载校园巴士站点")
                        .controlSize(.large)
                    Text("稍后就能在地图上查看所有车站。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView {
                    Label("巴士地图暂时不可用", systemImage: "bus")
                } description: {
                    Text(errorMessage ?? "未能获取车站数据。")
                } actions: {
                    Button("重新加载", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 20, y: 10)
    }
}

// MARK: - Map Annotations

struct BusStopMarker: View {
    static let annotationHitSize: CGFloat = 44
    private static let compactGlyphSize: CGFloat = 24
    private static let expandedGlyphSize: CGFloat = 40
    private static let inlineLabelSpacing: CGFloat = 4
    private static let selectedLabelSpacing: CGFloat = 12
    private static let labelAnimation: Animation = .snappy(duration: 0.2, extraBounce: 0)
    private static let visibilityAnimation: Animation = .easeInOut(duration: 0.18)
    static let selectionLayoutAnimation: Animation = .spring(response: 0.34, dampingFraction: 0.82)

    // Keep the map anchored to a stable point, then animate the marker inside that canvas.
    static var selectedAnnotationBottomInset: CGFloat {
        max(
            0,
            BusStopGlyph.bubblePointerOffsetY - (Self.annotationHitSize - Self.expandedGlyphSize) / 2
        )
    }

    static var selectedAnnotationAnchorOffsetY: CGFloat {
        Self.annotationHitSize + Self.selectedAnnotationBottomInset
    }

    static var unselectedAnnotationOffsetY: CGFloat {
        Self.selectedAnnotationAnchorOffsetY - Self.annotationHitSize / 2
    }

    static var annotationCanvasHeight: CGFloat {
        Self.unselectedAnnotationOffsetY + Self.annotationHitSize
    }

    static var annotationAnchor: UnitPoint {
        UnitPoint(
            x: 0.5,
            y: Self.selectedAnnotationAnchorOffsetY / Self.annotationCanvasHeight
        )
    }

    let badges: [BusRouteBadge]
    let showsMarker: Bool
    let isSelected: Bool
    let showsInlineLabels: Bool
    let animationToken: Int

    private var hasBadges: Bool {
        !badges.isEmpty
    }

    private var routeStyle: BusRouteStyle {
        .campusShuttle
    }

    private var inlineLabelWidth: CGFloat {
        BusRouteBadgeStrip.estimatedWidth(for: badges, prominent: false)
    }

    private var selectedLabelHeight: CGFloat {
        BusRouteBadgeStrip.estimatedHeight(prominent: true)
    }

    private var inlineLabelOffsetX: CGFloat {
        Self.compactGlyphSize / 2 + Self.inlineLabelSpacing + inlineLabelWidth / 2
    }

    private var selectedLabelOffsetY: CGFloat {
        Self.expandedGlyphSize / 2 + Self.selectedLabelSpacing + selectedLabelHeight / 2
    }

    private var showsInlineBadgeStrip: Bool {
        hasBadges && !isSelected && showsInlineLabels
    }

    private var showsSelectedBadgeStrip: Bool {
        hasBadges && isSelected
    }

    static func inlineLabelFootprint(for badges: [BusRouteBadge]) -> CGSize? {
        guard !badges.isEmpty else {
            return nil
        }

        return CGSize(
            width: BusRouteBadgeStrip.estimatedWidth(for: badges, prominent: false),
            height: BusRouteBadgeStrip.estimatedHeight(prominent: false)
        )
    }

    static func inlineLabelOffsetX(for badges: [BusRouteBadge]) -> CGFloat {
        guard let footprint = inlineLabelFootprint(for: badges) else {
            return 0
        }

        return Self.compactGlyphSize / 2 + Self.inlineLabelSpacing + footprint.width / 2
    }

    static func selectedLabelFootprint(for badges: [BusRouteBadge]) -> CGSize? {
        guard !badges.isEmpty else {
            return nil
        }

        return CGSize(
            width: BusRouteBadgeStrip.estimatedWidth(for: badges, prominent: true),
            height: BusRouteBadgeStrip.estimatedHeight(prominent: true)
        )
    }

    static func markerCollisionRect(
        at anchorPoint: CGPoint,
        isSelected: Bool
    ) -> CGRect {
        if isSelected {
            return CGRect(
                x: anchorPoint.x - Self.annotationHitSize / 2,
                y: anchorPoint.y - Self.selectedAnnotationAnchorOffsetY,
                width: Self.annotationHitSize,
                height: Self.annotationHitSize
            )
        }

        return CGRect(
            x: anchorPoint.x - Self.annotationHitSize / 2,
            y: anchorPoint.y - Self.annotationHitSize / 2,
            width: Self.annotationHitSize,
            height: Self.annotationHitSize
        )
    }

    static func inlineLabelCollisionRect(
        at anchorPoint: CGPoint,
        badges: [BusRouteBadge]
    ) -> CGRect? {
        guard let footprint = inlineLabelFootprint(for: badges) else {
            return nil
        }

        return CGRect(
            x: anchorPoint.x + inlineLabelOffsetX(for: badges) - footprint.width / 2,
            y: anchorPoint.y - footprint.height / 2,
            width: footprint.width,
            height: footprint.height
        )
    }

    static func selectedCollisionRect(
        at anchorPoint: CGPoint,
        badges: [BusRouteBadge]
    ) -> CGRect {
        var collisionRect = markerCollisionRect(
            at: anchorPoint,
            isSelected: true
        )

        if let footprint = selectedLabelFootprint(for: badges) {
            let selectedBadgeRect = CGRect(
                x: anchorPoint.x - footprint.width / 2,
                y: anchorPoint.y + BusStopGlyph.bubblePointerOffsetY,
                width: footprint.width,
                height: footprint.height
            )
            collisionRect = collisionRect.union(selectedBadgeRect)
        }

        return collisionRect.insetBy(dx: -4, dy: -4)
    }

    var body: some View {
        BusStopGlyph(
            style: routeStyle,
            isSelected: isSelected,
            animationToken: animationToken
        )
        .overlay {
            if hasBadges {
                BusRouteBadgeStrip(
                    badges: badges,
                    prominent: false
                )
                .fixedSize()
                .offset(
                    x: showsInlineBadgeStrip ? inlineLabelOffsetX : inlineLabelOffsetX - 8,
                    y: 0
                )
                .opacity(showsInlineBadgeStrip ? 1 : 0)
                .scaleEffect(showsInlineBadgeStrip ? 1 : 0.96, anchor: .leading)
                .animation(Self.labelAnimation, value: showsInlineBadgeStrip)
            }
        }
        .overlay {
            if hasBadges {
                BusRouteBadgeStrip(
                    badges: badges,
                    prominent: true
                )
                .fixedSize()
                .offset(
                    x: 0,
                    y: showsSelectedBadgeStrip ? selectedLabelOffsetY : selectedLabelOffsetY - 6
                )
                .opacity(showsSelectedBadgeStrip ? 1 : 0)
                .scaleEffect(showsSelectedBadgeStrip ? 1 : 0.96, anchor: .top)
                .animation(Self.labelAnimation, value: showsSelectedBadgeStrip)
            }
        }
        .scaleEffect(showsMarker ? 1 : 0.9)
        .opacity(showsMarker ? 1 : 0)
        .animation(Self.visibilityAnimation, value: showsMarker)
        .shadow(
            color: Color.black.opacity(isSelected ? 0.22 : 0.14),
            radius: isSelected ? 11 : 6,
            y: isSelected ? 6 : 3
        )
    }
}

private struct BusStopGlyph: View {
    private static let compactGlyphSize: CGFloat = 20
    private static let expandedGlyphSize: CGFloat = 40
    static let bubblePointerOffsetY: CGFloat = 6

    let style: BusRouteStyle
    let isSelected: Bool
    let animationToken: Int

    private var glyphSize: CGFloat {
        isSelected ? Self.expandedGlyphSize : Self.compactGlyphSize
    }

    private var iconSize: CGFloat {
        isSelected ? 16 : 9
    }

    var body: some View {
        RoundedRectangle(cornerRadius: isSelected ? 12 : 8, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(style.tint) : AnyShapeStyle(Color.white))
            .frame(width: glyphSize, height: glyphSize)
            .overlay {
                RoundedRectangle(cornerRadius: isSelected ? 12 : 8, style: .continuous)
                    .stroke(style.tint.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
            }
            .overlay {
                Image(systemName: "bus.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : style.tint)
            }
            .phaseAnimator(
                isSelected ? [0.0, -5.0, 3.5, -1.5, 0.0] : [0.0],
                trigger: animationToken
            ) { content, angle in
                content.rotationEffect(.degrees(angle))
            } animation: { _ in
                .smooth(duration: 0.24)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isSelected)
            .frame(width: Self.expandedGlyphSize, height: Self.expandedGlyphSize)
            .overlay(alignment: .bottom) {
                BusBubblePointer()
                    .fill(style.tint)
                    .frame(width: 12, height: 7)
                    .offset(y: Self.bubblePointerOffsetY)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
            }
    }
}

struct BusRouteStationDot: View {
    let style: BusRouteStyle

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(style.tint, lineWidth: 2)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
    }
}

struct BusRealtimeVehicleMarker: View {
    private static let iconFrameSize: CGFloat = 34
    private static let hitFrameSize: CGFloat = 44

    let vehicle: BusAPI.RealtimeVehicle

    private var routeTint: Color {
        BusRouteStyle.campusShuttle.tint
    }

    private var heading: Angle {
        .degrees(vehicle.angle)
    }

    var body: some View {
        Image(systemName: "bus.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.iconFrameSize, height: Self.iconFrameSize)
            .background(routeTint, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .rotationEffect(heading)
            .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
            .frame(width: Self.hitFrameSize, height: Self.hitFrameSize)
            .contentShape(Rectangle())
    }
}

private struct BusRouteBadgeStrip: View {
    private static let maximumVisibleBadges = 3

    let badges: [BusRouteBadge]
    let prominent: Bool

    private var visibleBadges: [BusRouteBadge] {
        Array(badges.prefix(Self.maximumVisibleBadges))
    }

    var body: some View {
        HStack(spacing: prominent ? 6 : 4) {
            ForEach(visibleBadges) { badge in
                BusLineShield(
                    title: badge.title,
                    style: .campusShuttle,
                    prominent: prominent
                )
            }
        }
    }

    static func estimatedWidth(
        for badges: [BusRouteBadge],
        prominent: Bool
    ) -> CGFloat {
        let visibleBadges = Array(badges.prefix(Self.maximumVisibleBadges))
        let spacing = prominent ? 6.0 : 6.0

        return visibleBadges.enumerated().reduce(0) { partialResult, element in
            let badge = element.element
            let textWidth = CGFloat(max(badge.title.count, 1)) * (prominent ? 11 : 10)
            let horizontalPadding = prominent ? 18.0 : 16.0
            let badgeWidth = textWidth + horizontalPadding

            return partialResult + badgeWidth + (element.offset == 0 ? 0 : spacing)
        }
    }

    static func estimatedHeight(prominent: Bool) -> CGFloat {
        prominent ? 22 : 22
    }
}
