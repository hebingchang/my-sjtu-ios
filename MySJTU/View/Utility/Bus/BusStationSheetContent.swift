//
//  BusStationSheetContent.swift
//  MySJTU
//

import SwiftUI

struct BusStationSheetContent: View {
    let station: BusAPI.Station
    let state: BusStationPanelState
    let onRefresh: () -> Void
    let onSelectLineDetail: (BusLineDetailSelection) -> Void

    private var cards: [BusDepartureCard] {
        state.cachedData?.cards ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage = state.errorMessage {
                    BusSheetStatusBanner(
                        title: cards.isEmpty ? "线路信息加载失败" : "刷新失败",
                        message: errorMessage,
                        isLoading: false,
                        onRefresh: onRefresh
                    )
                } else if state.isLoading {
                    BusSheetStatusBanner(
                        title: "正在获取线路信息",
                        message: "正在获取线路信息与发车时刻表。",
                        isLoading: true,
                        onRefresh: nil
                    )
                }

                if cards.isEmpty {
                    if state.isLoading {
                        VStack(spacing: 14) {
                            BusCardPlaceholder()
                            BusCardPlaceholder()
                        }
                    } else {
                        BusEmptyStateCard()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(cards) { card in
                            BusDepartureCardView(
                                station: station,
                                card: card,
                                onSelectLineDetail: onSelectLineDetail
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }
}

struct BusSheetNavigationTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: subtitle == nil ? 0 : 2) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct BusSheetStatusBanner: View {
    let title: String
    let message: String
    let isLoading: Bool
    let onRefresh: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let onRefresh {
                Button("重试", action: onRefresh)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .background(Color.secondarySystemBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BusEmptyStateCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("暂无发车信息")
                .font(.headline)
            Text("该线路可能已经结束运营，或当前站点暂无可用发车计划。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondarySystemBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct BusCardPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.secondarySystemBackground)
            .frame(height: 168)
            .overlay {
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.quaternarySystemFill)
                        .frame(width: 140, height: 26)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.quaternarySystemFill)
                        .frame(height: 48)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.quaternarySystemFill)
                        .frame(height: 48)
                }
                .padding(18)
                .redacted(reason: .placeholder)
            }
    }
}
