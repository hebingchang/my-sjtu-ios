//
//  BusDepartureCardView.swift
//  MySJTU
//

import SwiftUI

private func uniqueTimetableTypes(
    from departures: [BusDepartureCard.Departure]
) -> [String] {
    var seenTypes = Set<String>()

    return departures.compactMap(\.type).filter { type in
        !type.isEmpty && seenTypes.insert(type).inserted
    }
}

struct BusDepartureCardView: View {
    let station: BusAPI.Station
    let card: BusDepartureCard
    let onSelectLineDetail: (BusLineDetailSelection) -> Void
    private let rows: [BusDirectionRowModel]

    init(
        station: BusAPI.Station,
        card: BusDepartureCard,
        onSelectLineDetail: @escaping (BusLineDetailSelection) -> Void
    ) {
        self.station = station
        self.card = card
        self.onSelectLineDetail = onSelectLineDetail
        rows = Self.makeRows(
            station: station,
            card: card
        )
    }

    private var routeStyle: BusRouteStyle {
        .campusShuttle
    }

    private static func makeRows(
        station: BusAPI.Station,
        card: BusDepartureCard
    ) -> [BusDirectionRowModel] {
        card.directions.flatMap { direction in
            let groupedDestinations = direction.destinationGroups
            let destinationOptions = groupedDestinations.map {
                BusLineDestinationOption(
                    code: $0.destinationCode,
                    name: $0.destinationName,
                    timetableTypes: uniqueTimetableTypes(from: $0.departures)
                )
            }

            if groupedDestinations.isEmpty {
                return [
                    BusDirectionRowModel(
                        id: direction.id,
                        destinationName: direction.endStation,
                        subtitle: nil,
                        timeText: "暂无",
                        relativeText: nil,
                        isAvailable: false,
                        sortExecutionDate: nil,
                        sortTimeInt: nil,
                        selection: BusLineDetailSelection(
                            station: station,
                            currentStopID: direction.departures.first?.stationID,
                            lineCode: card.lineCode,
                            lineName: card.name,
                            badgeTitle: card.badgeTitle,
                            direction: direction.direction,
                            directionTitle: direction.title,
                            lineEndStation: direction.endStation,
                            destinationCode: direction.id,
                            destinationName: direction.endStation,
                            destinationOptions: [
                                BusLineDestinationOption(
                                    code: direction.id,
                                    name: direction.endStation,
                                    timetableTypes: uniqueTimetableTypes(from: direction.departures)
                                )
                            ],
                            directionFilterMode: .all
                        )
                    )
                ]
            }

            return groupedDestinations.map { destinationGroup in
                let firstDeparture = destinationGroup.departures.first(where: { $0.hasUpcomingDeparture })
                    ?? destinationGroup.departures.first
                let subtitle = direction.title == destinationGroup.destinationName ? nil : direction.title
                let isSpecialDirection = normalizedBusStationName(destinationGroup.destinationName)
                    != normalizedBusStationName(direction.endStation)

                return BusDirectionRowModel(
                    id: "\(direction.id)-\(destinationGroup.id)",
                    destinationName: destinationGroup.destinationName,
                    subtitle: subtitle,
                    timeText: firstDeparture?.displayTimeText ?? "暂无",
                    relativeText: firstDeparture.flatMap { departure in
                        BusScheduleClock.relativeDescription(for: departure)
                    },
                    isAvailable: firstDeparture?.hasUpcomingDeparture == true,
                    sortExecutionDate: firstDeparture?.executionDate,
                    sortTimeInt: firstDeparture?.timeInt,
                    selection: BusLineDetailSelection(
                        station: station,
                        currentStopID: firstDeparture?.stationID,
                        lineCode: card.lineCode,
                        lineName: card.name,
                        badgeTitle: card.badgeTitle,
                        direction: direction.direction,
                        directionTitle: direction.title,
                        lineEndStation: direction.endStation,
                        destinationCode: destinationGroup.destinationCode,
                        destinationName: destinationGroup.destinationName,
                        destinationOptions: destinationOptions,
                        directionFilterMode: isSpecialDirection ? .special : .all
                    )
                )
            }
        }
        .enumerated()
        .sorted { lhs, rhs in
            busDirectionRowSort(
                lhs: lhs.element,
                rhs: rhs.element,
                lhsFallbackIndex: lhs.offset,
                rhsFallbackIndex: rhs.offset
            )
        }
        .map(\.element)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                BusLineShield(
                    title: card.badgeTitle,
                    style: routeStyle,
                    prominent: true
                )

                Text(card.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                BusDirectionListRow(row: row)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectLineDetail(row.selection)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("查看该线路方向详情")
                    .accessibilityAction {
                        onSelectLineDetail(row.selection)
                    }

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.clear)
                .glassEffect(in: .rect(cornerRadius: 26, style: .continuous))
        }
    }
}

private struct BusDirectionRowModel: Identifiable {
    let id: String
    let destinationName: String
    let subtitle: String?
    let timeText: String
    let relativeText: String?
    let isAvailable: Bool
    let sortExecutionDate: String?
    let sortTimeInt: Int?
    let selection: BusLineDetailSelection
}

private struct BusDirectionListRow: View {
    let row: BusDirectionRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("开往 \(row.destinationName)")
                    .font(.body.weight(.regular))
                    .lineLimit(2)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.timeText)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(row.isAvailable ? .primary : .secondary)

                if let relativeText = row.relativeText {
                    Text(relativeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private func busDirectionRowSort(
    lhs: BusDirectionRowModel,
    rhs: BusDirectionRowModel,
    lhsFallbackIndex: Int,
    rhsFallbackIndex: Int
) -> Bool {
    switch (
        (lhs.sortExecutionDate, lhs.sortTimeInt),
        (rhs.sortExecutionDate, rhs.sortTimeInt)
    ) {
    case let ((lhsExecutionDate?, lhsTimeInt?), (rhsExecutionDate?, rhsTimeInt?)):
        if lhsExecutionDate != rhsExecutionDate {
            return lhsExecutionDate < rhsExecutionDate
        }

        if lhsTimeInt != rhsTimeInt {
            return lhsTimeInt < rhsTimeInt
        }

    case ((.some, .some), _):
        return true

    case (_, (.some, .some)):
        return false

    default:
        break
    }

    return lhsFallbackIndex < rhsFallbackIndex
}
