//
//  BusListView.swift
//  MySJTU
//

import SwiftUI
import MapKit
import UIKit

struct BusListView: View {
    private struct StationAnnotationVisibility {
        let showsMarker: Bool
        let showsInlineLabels: Bool
    }

    private enum MapSelection: Hashable {
        case station(Int)
        case lineDetailStation
    }

    private struct StationAnnotationLayoutState {
        let orderedStations: [BusAPI.Station]
        let visibilityByID: [Int: StationAnnotationVisibility]
    }

    private struct LineDetailMapState {
        let route: BusAPI.Route?
        let selectedLineStation: BusAPI.LineStation?
        let routeStations: [BusAPI.LineStation]
        let realtimeVehicles: [BusAPI.RealtimeVehicle]
    }

    private static let compactSheetDetent: PresentationDetent = .height(186)
    private static let stationLabelZoomThreshold: CLLocationDegrees = 0.0105
    private static let mediumLineDetailCenterDownwardCompensation: CGFloat = 16
    private static let defaultMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: 31.02223853775149,
            longitude: 121.4367061348467
        ),
        span: MKCoordinateSpan(
            latitudeDelta: 0.018,
            longitudeDelta: 0.02
        )
    )
    private static let initialCameraAnimation: Animation = .smooth(duration: 0.6)
    private static let lineDetailSheetDetents: Set<PresentationDetent> = [.height(232), .medium, .large]

    @StateObject private var viewModel = BusMapViewModel()
    @Namespace private var mapScope
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultMapRegion)
    @State private var visibleRegion: MKCoordinateRegion? = Self.defaultMapRegion
    @State private var mapSelection: MapSelection?
    @State private var mapViewSize: CGSize = .zero
    @State private var mapViewFrame: CGRect = .zero
    @State private var stationSheetFrame: CGRect = .zero
    @State private var lineDetailSheetFrame: CGRect = .zero
    @State private var presentedStation: BusAPI.Station?
    @State private var presentedLineDetail: BusLineDetailSelection?
    @State private var selectedSheetDetent: PresentationDetent = Self.compactSheetDetent
    @State private var selectedLineSheetDetent: PresentationDetent = .medium
    @State private var selectionAnimationToken: Int = 0
    @State private var hasConfiguredInitialCamera: Bool = false
    @State private var routeRestoreRegion: MKCoordinateRegion?
    @State private var lineDetailLoadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Layout State

    private var shouldShowStationLabels: Bool {
        (visibleRegion?.span.longitudeDelta ?? Self.defaultMapRegion.span.longitudeDelta)
        <= Self.stationLabelZoomThreshold
    }

    private var currentMapBottomObstructionFraction: CLLocationDegrees {
        let mapHeight = max(mapViewFrame.height, mapViewSize.height)
        guard mapHeight > 0 else {
            return 0
        }

        let obstructionHeight = min(
            max(currentMapBottomObstructionHeight, 0),
            mapHeight
        )

        return CLLocationDegrees(obstructionHeight / mapHeight)
    }

    private var currentMapBottomObstructionHeight: CGFloat {
        guard !mapViewFrame.isEmpty else {
            return 0
        }

        return min(
            max(
                sheetOverlapHeight(for: stationSheetFrame),
                sheetOverlapHeight(for: lineDetailSheetFrame)
            ),
            mapViewFrame.height
        )
    }

    private var currentMapCenterDownwardCompensationFraction: CLLocationDegrees {
        let mapHeight = max(mapViewFrame.height, mapViewSize.height)
        guard
            mapHeight > 0,
            presentedLineDetail != nil,
            selectedLineSheetDetent == .medium
        else {
            return 0
        }

        return CLLocationDegrees(
            min(Self.mediumLineDetailCenterDownwardCompensation, mapHeight / 2) / mapHeight
        )
    }

    private var stationAnnotationLayoutState: StationAnnotationLayoutState {
        let selectedStationID = presentedStation?.id
        let orderedStations = viewModel.stations
            .sorted { lhs, rhs in
                let lhsIsSelected = lhs.id == selectedStationID
                let rhsIsSelected = rhs.id == selectedStationID
                if lhsIsSelected != rhsIsSelected {
                    return !lhsIsSelected && rhsIsSelected
                }

                return lhs.id < rhs.id
            }
        let visibilityByID = collisionAdjustedVisibilityByID(
            orderedStations: orderedStations
        )
        return StationAnnotationLayoutState(
            orderedStations: orderedStations,
            visibilityByID: visibilityByID
        )
    }

    // MARK: - Bindings

    private var presentedStationBinding: Binding<BusAPI.Station?> {
        Binding(
            get: { presentedStation },
            set: { newValue in
                if let newValue {
                    presentedStation = newValue
                } else {
                    deselectStation()
                }
            }
        )
    }

    private var presentedLineDetailBinding: Binding<BusLineDetailSelection?> {
        Binding(
            get: { presentedLineDetail },
            set: { newValue in
                if let newValue {
                    presentedLineDetail = newValue
                } else {
                    dismissLineDetail()
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        let stationAnnotationLayout = stationAnnotationLayoutState
        let lineDetailMapState = presentedLineDetail.map {
            makeLineDetailMapState(for: $0)
        }

        GeometryReader { geometry in
            ZStack {
                ZStack {
                    Map(position: $cameraPosition, selection: $mapSelection, scope: mapScope) {
                        mapContent(
                            stationAnnotationLayout: stationAnnotationLayout,
                            lineDetailMapState: lineDetailMapState
                        )
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapPitchToggle()
                        MapScaleView()
                    }
                    .tint(BusRouteStyle.campusShuttle.tint)
                    .onMapCameraChange(frequency: .continuous) { context in
                        updateVisibleRegion(context.region)
                    }

                    if viewModel.stations.isEmpty, let errorMessage = viewModel.stationLoadError {
                        BusStationLoadOverlay(
                            isLoading: false,
                            errorMessage: errorMessage
                        ) {
                            reloadStations()
                        }
                    }
                }
            }
            .mapScope(mapScope)
            .onAppear {
                updateMapViewSize(geometry.size)
                updateMapViewFrame(geometry.frame(in: .global))
            }
            .onChange(of: geometry.size) { _, newSize in
                updateMapViewSize(newSize)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { _, newFrame in
                updateMapViewFrame(newFrame)
            }
        }
        .background(Color.systemGroupedBackground)
        .navigationTitle("校园巴士")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismissView) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                }
            }
        }
        .task {
            await viewModel.loadStationsIfNeeded()
        }
        .onChange(of: viewModel.stations) { _, stations in
            configureInitialCameraIfNeeded(with: stations)
        }
        .onChange(of: mapSelection) { _, selection in
            handleMapSelection(selection)
        }
        .onDisappear {
            cancelLineDetailTask()
            viewModel.deactivateRealtimeMonitor()
        }
        .sheet(item: presentedStationBinding) { station in
            NavigationStack {
                BusStationSheetContent(
                    station: station,
                    state: viewModel.panelState(for: station),
                    onRefresh: {
                        viewModel.loadPanel(for: station, forceRefresh: true)
                    },
                    onSelectLineDetail: { selection in
                        presentLineDetail(selection)
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        BusSheetNavigationTitle(
                            title: station.name,
                            subtitle: nil
                        )
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            deselectStation()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("关闭")
                    }
                }
                .onDisappear {
                    resetStationSheetFrame()
                    resetLineDetailSheetFrame()
                }
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { _, newFrame in
                updateStationSheetFrame(newFrame)
            }
            .presentationDetents(
                [Self.compactSheetDetent, .medium, .large],
                selection: $selectedSheetDetent
            )
            .interactiveDismissDisabled()
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .sheet(item: presentedLineDetailBinding) { selection in
                NavigationStack {
                    BusLineDetailSheetContent(
                        selection: selection,
                        state: viewModel.lineDetailState(for: selection),
                        onRefresh: {
                            presentLineDetail(selection, forceRefresh: true)
                        },
                        onSelectDirectionFilter: { mode in
                            updatePresentedLineDetailDirectionFilter(mode)
                        }
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismissLineDetail()
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "chevron.left")
                                    Text("返回")
                                }
                            }
                        }

                        ToolbarItem(placement: .principal) {
                            BusSheetNavigationTitle(
                                title: selection.lineName,
                                subtitle: selection.sheetSubtitle
                            )
                        }
                    }
                }
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global)
                } action: { oldFrame, newFrame in
                    updateLineDetailSheetFrame(newFrame)

                    if oldFrame.isEmpty, !newFrame.isEmpty {
                        refocusPresentedLineDetailIfNeeded(animated: false)
                    }
                }
                .onDisappear {
                    resetLineDetailSheetFrame()
                }
                .presentationDetents(
                    Self.lineDetailSheetDetents,
                    selection: $selectedLineSheetDetent
                )
                .interactiveDismissDisabled()
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
    }

    // MARK: - Map Content

    @MapContentBuilder
    private func mapContent(
        stationAnnotationLayout: StationAnnotationLayoutState,
        lineDetailMapState: LineDetailMapState?
    ) -> some MapContent {
        UserAnnotation()

        if let presentedLineDetail, let lineDetailMapState {
            lineDetailMapContent(
                for: presentedLineDetail,
                state: lineDetailMapState
            )
        } else {
            ForEach(stationAnnotationLayout.orderedStations) { station in
                stationAnnotation(
                    for: station,
                    visibility: stationAnnotationLayout.visibilityByID[station.id]
                    ?? defaultAnnotationVisibility(for: station)
                )
            }
        }
    }

    private func stationMarkerView(
        for station: BusAPI.Station,
        visibility: StationAnnotationVisibility
    ) -> some View {
        let isSelected = presentedStation?.id == station.id
        let isActivated = isSelected
        return annotationMarkerView(
            badges: station.routeBadges,
            showsMarker: visibility.showsMarker,
            isSelected: isSelected,
            showsInlineLabels: visibility.showsInlineLabels,
            animationToken: selectionAnimationToken
        )
        .accessibilityHidden(!visibility.showsMarker)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.name)
        .accessibilityValue(Text(stationAccessibilityValue(for: station)))
        .accessibilityHint(Text(isActivated ? "关闭该站发车信息" : "查看该站发车信息"))
    }

    private func annotationMarkerView(
        badges: [BusRouteBadge],
        showsMarker: Bool,
        isSelected: Bool,
        showsInlineLabels: Bool,
        animationToken: Int
    ) -> some View {
        BusStopMarker(
            badges: badges,
            showsMarker: showsMarker,
            isSelected: isSelected,
            showsInlineLabels: showsInlineLabels,
            animationToken: animationToken
        )
        .frame(
            minWidth: BusStopMarker.annotationHitSize,
            minHeight: BusStopMarker.annotationHitSize
        )
        .padding(
            .bottom,
            isSelected ? BusStopMarker.selectedAnnotationBottomInset : 0
        )
        .offset(y: isSelected ? 0 : BusStopMarker.unselectedAnnotationOffsetY)
        .frame(
            minWidth: BusStopMarker.annotationHitSize,
            minHeight: BusStopMarker.annotationCanvasHeight,
            alignment: .top
        )
        .zIndex(isSelected ? 1 : 0)
        .animation(BusStopMarker.selectionLayoutAnimation, value: isSelected)
    }

    @MapContentBuilder
    private func stationAnnotation(
        for station: BusAPI.Station,
        visibility: StationAnnotationVisibility
    ) -> some MapContent {
        Annotation(
            station.name,
            coordinate: station.coordinate,
            anchor: BusStopMarker.annotationAnchor
        ) {
            stationMarkerView(
                for: station,
                visibility: visibility
            )
        }
        .annotationTitles(.hidden)
        .tag(MapSelection.station(station.id))
    }

    @MapContentBuilder
    private func lineDetailMapContent(
        for selection: BusLineDetailSelection,
        state: LineDetailMapState
    ) -> some MapContent {
        if let route = state.route,
           !route.coordinates.isEmpty {
            MapPolyline(coordinates: route.coordinates)
                .stroke(
                    BusRouteStyle.campusShuttle.tint,
                    style: StrokeStyle(
                        lineWidth: 5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }

        ForEach(state.routeStations) { station in
            Annotation(
                station.station.name,
                coordinate: station.station.location.coordinate,
                anchor: .center
            ) {
                BusRouteStationDot(style: .campusShuttle)
            }
            .annotationTitles(.hidden)
        }

        ForEach(state.realtimeVehicles) { vehicle in
            Annotation(
                vehicle.vehicleCode,
                coordinate: vehicle.coordinate,
                anchor: .center
            ) {
                BusRealtimeVehicleMarker(vehicle: vehicle)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .animation(.easeInOut(duration: 0.9), value: vehicle.coordinate.latitude)
                    .animation(.easeInOut(duration: 0.9), value: vehicle.coordinate.longitude)
                    .animation(.easeInOut(duration: 0.35), value: vehicle.angle)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("实时巴士")
                    .accessibilityHint("地图上的实时巴士位置")
            }
            .annotationTitles(.hidden)
        }

        Annotation(
            state.selectedLineStation?.station.name ?? selection.station.name,
            coordinate: state.selectedLineStation?.station.location.coordinate ?? selection.station.coordinate,
            anchor: BusStopMarker.annotationAnchor
        ) {
            annotationMarkerView(
                badges: [],
                showsMarker: true,
                isSelected: true,
                showsInlineLabels: false,
                animationToken: selectionAnimationToken
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.selectedLineStation?.station.name ?? selection.station.name)
            .accessibilityHint("返回站点发车信息")
        }
        .annotationTitles(.hidden)
        .tag(MapSelection.lineDetailStation)
    }

    private func makeLineDetailMapState(
        for selection: BusLineDetailSelection
    ) -> LineDetailMapState {
        let cachedData = viewModel.lineDetailState(for: selection).cachedData
        let selectedLineStation = resolvedCurrentLineStation(
            for: selection,
            in: cachedData?.lineStations ?? []
        )

        return LineDetailMapState(
            route: cachedData?.route,
            selectedLineStation: selectedLineStation,
            routeStations: routeStations(for: selection, from: cachedData),
            realtimeVehicles: viewModel.realtimeVehicles(for: selection)
        )
    }

    private func routeStations(
        for selection: BusLineDetailSelection,
        from data: BusLinePanelData?
    ) -> [BusAPI.LineStation] {
        guard let data else {
            return []
        }

        let selectedLineStationIDs = Set(
            resolvedCurrentLineStations(for: selection, in: data.lineStations).map(\.id)
        )

        return destinationFilteredLineStations(
            for: selection,
            in: data.lineStations
        )
        .filter { lineStation in
            !selectedLineStationIDs.contains(lineStation.id)
        }
    }

    // MARK: - Presentation

    private func selectStation(_ station: BusAPI.Station) {
        if presentedStation?.id == station.id {
            if selectedSheetDetent != .medium {
                selectedSheetDetent = .medium
            }
            viewModel.loadPanel(for: station, forceRefresh: true)
            return
        }

        dismissLineDetail(restoreMap: false)
        if selectedSheetDetent != Self.compactSheetDetent {
            selectedSheetDetent = Self.compactSheetDetent
        }
        presentedStation = station
        viewModel.loadPanel(for: station)
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator.prepare()
        selectionAnimationToken &+= 1
        feedbackGenerator.impactOccurred(intensity: 0.9)
    }

    private func deselectStation(
        restoreLineDetailMap: Bool = true
    ) {
        guard presentedStation != nil || presentedLineDetail != nil else {
            return
        }
        dismissLineDetail(restoreMap: restoreLineDetailMap)
        if selectedSheetDetent != Self.compactSheetDetent {
            selectedSheetDetent = Self.compactSheetDetent
        }
        presentedStation = nil
    }

    private func handleMapSelection(
        _ selection: MapSelection?
    ) {
        guard let selection else {
            return
        }

        switch selection {
        case .station(let stationID):
            guard let station = viewModel.stations.first(where: { $0.id == stationID }) else {
                clearMapSelection()
                return
            }

            if station.id == presentedStation?.id {
                deselectStation()
            } else {
                selectStation(station)
            }

        case .lineDetailStation:
            dismissLineDetail()
        }

        clearMapSelection()
    }

    private func clearMapSelection() {
        guard mapSelection != nil else {
            return
        }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                mapSelection = nil
            }
        }
    }

    private func presentLineDetail(
        _ selection: BusLineDetailSelection,
        forceRefresh: Bool = false
    ) {
        if presentedLineDetail == nil {
            routeRestoreRegion = visibleRegion
            ?? (viewModel.stations.isEmpty ? Self.defaultMapRegion : mapRegion(for: viewModel.stations))
        }

        if selectedSheetDetent == .large {
            selectedSheetDetent = .medium
        }
        if presentedLineDetail != selection {
            presentedLineDetail = selection
        }
        viewModel.activateRealtimeMonitor(for: selection)
        if selectedLineSheetDetent != .medium {
            selectedLineSheetDetent = .medium
        }
        cancelLineDetailTask()

        lineDetailLoadTask = Task {
            let data = await viewModel.loadLineDetail(
                for: selection,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard presentedLineDetail?.cacheKey == selection.cacheKey else {
                    return
                }

                if let data {
                    focusOnLineDetail(
                        data,
                        selection: selection
                    )
                } else {
                    focusOnLineDetailFallback(selection)
                }
            }
        }
    }

    private func updatePresentedLineDetailDirectionFilter(
        _ mode: BusLineDirectionFilterMode
    ) {
        guard let selection = presentedLineDetail else {
            return
        }

        let updatedSelection = selection.updatingDirectionFilter(mode)
        guard updatedSelection != selection else {
            return
        }

        presentedLineDetail = updatedSelection
    }

    private func dismissLineDetail(
        restoreMap: Bool = true
    ) {
        guard presentedLineDetail != nil || routeRestoreRegion != nil else {
            return
        }

        cancelLineDetailTask()
        viewModel.deactivateRealtimeMonitor()
        if presentedLineDetail != nil {
            presentedLineDetail = nil
        }
        if selectedLineSheetDetent != .medium {
            selectedLineSheetDetent = .medium
        }

        let regionToRestore = routeRestoreRegion
        routeRestoreRegion = nil

        guard restoreMap, let regionToRestore else {
            return
        }

        applyMapRegion(regionToRestore)
    }

    private func focusOnLineDetail(
        _ data: BusLinePanelData,
        selection: BusLineDetailSelection,
        animated: Bool = true
    ) {
        let currentCoordinate = resolvedCurrentLineStation(
            for: selection,
            in: data.lineStations
        )?.station.location.coordinate ?? selection.station.coordinate
        let coordinates = destinationFilteredLineStations(
            for: selection,
            in: data.lineStations
        )
            .map { $0.station.location.coordinate }
        + [currentCoordinate]

        guard !coordinates.isEmpty else {
            focusOnLineDetailFallback(
                selection,
                animated: animated
            )
            return
        }

        applyMapRegion(
            mapRegion(
                for: coordinates,
                fallbackCenter: currentCoordinate,
                minimumSpan: MKCoordinateSpan(
                    latitudeDelta: 0.007,
                    longitudeDelta: 0.008
                ),
                fitToVisibleArea: true
            ),
            animated: animated
        )
    }

    private func focusOnLineDetailFallback(
        _ selection: BusLineDetailSelection,
        animated: Bool = true
    ) {
        applyMapRegion(
            mapRegion(
                for: [selection.station.coordinate],
                fallbackCenter: selection.station.coordinate,
                minimumSpan: MKCoordinateSpan(
                    latitudeDelta: 0.007,
                    longitudeDelta: 0.008
                ),
                fitToVisibleArea: true
            ),
            animated: animated
        )
    }

    private func applyMapRegion(
        _ region: MKCoordinateRegion,
        animated: Bool = true
    ) {
        if animated {
            withAnimation(Self.initialCameraAnimation) {
                cameraPosition = .region(region)
                updateVisibleRegion(region)
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                cameraPosition = .region(region)
                updateVisibleRegion(region)
            }
        }
    }

    // MARK: - View Actions

    private func configureInitialCameraIfNeeded(with stations: [BusAPI.Station]) {
        guard !stations.isEmpty, !hasConfiguredInitialCamera else {
            return
        }

        let region = mapRegion(for: stations)
        hasConfiguredInitialCamera = true

        withAnimation(Self.initialCameraAnimation) {
            cameraPosition = .region(region)
            updateVisibleRegion(region)
        }
    }

    private func stationAccessibilityValue(for station: BusAPI.Station) -> String {
        let routeDescription: String
        if station.routeBadges.isEmpty {
            routeDescription = "无线路信息"
        } else {
            let titles = station.routeBadges.map(\.title).joined(separator: "、")
            routeDescription = "线路 \(titles)"
        }

        if presentedStation?.id == station.id {
            return "\(routeDescription)，已选中"
        }

        return routeDescription
    }

    private func reloadStations() {
        Task {
            await viewModel.reloadStations()
        }
    }

    private func dismissView() {
        deselectStation(restoreLineDetailMap: false)
        dismiss()
    }

    // MARK: - Geometry Tracking

    private func updateMapViewSize(_ size: CGSize) {
        guard
            size.width > 0,
            size.height > 0,
            mapViewSize != size
        else {
            return
        }

        mapViewSize = size
    }

    private func updateMapViewFrame(_ frame: CGRect) {
        guard
            !frame.isEmpty,
            mapViewFrame != frame
        else {
            return
        }

        mapViewFrame = frame
    }

    private func updateVisibleRegion(_ region: MKCoordinateRegion) {
        guard !mapRegionEquals(visibleRegion, region) else {
            return
        }

        visibleRegion = region
    }

    private func updateStationSheetFrame(_ frame: CGRect) {
        guard
            !frame.isEmpty,
            stationSheetFrame != frame
        else {
            return
        }

        stationSheetFrame = frame
    }

    private func resetStationSheetFrame() {
        guard stationSheetFrame != .zero else {
            return
        }

        stationSheetFrame = .zero
    }

    private func updateLineDetailSheetFrame(_ frame: CGRect) {
        guard
            !frame.isEmpty,
            lineDetailSheetFrame != frame
        else {
            return
        }

        lineDetailSheetFrame = frame
    }

    private func resetLineDetailSheetFrame() {
        guard lineDetailSheetFrame != .zero else {
            return
        }

        lineDetailSheetFrame = .zero
    }

    // MARK: - Map Regions

    private func mapRegionEquals(
        _ lhs: MKCoordinateRegion?,
        _ rhs: MKCoordinateRegion
    ) -> Bool {
        guard let lhs else {
            return false
        }

        return lhs.center.latitude == rhs.center.latitude
        && lhs.center.longitude == rhs.center.longitude
        && lhs.span.latitudeDelta == rhs.span.latitudeDelta
        && lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }

    private func defaultAnnotationVisibility(for station: BusAPI.Station) -> StationAnnotationVisibility {
        StationAnnotationVisibility(
            showsMarker: true,
            showsInlineLabels: wantsInlineLabels(for: station)
        )
    }

    private func collisionAdjustedVisibilityByID(
        orderedStations: [BusAPI.Station]
    ) -> [Int: StationAnnotationVisibility] {
        var visibilityByID = Dictionary(
            uniqueKeysWithValues: orderedStations.map { station in
                (
                    station.id,
                    defaultAnnotationVisibility(for: station)
                )
            }
        )

        guard let selectedStation = presentedStation,
              let selectedAnchorPoint = projectedMapPoint(for: selectedStation.coordinate) else {
            return visibilityByID
        }

        let selectedCollisionRect = BusStopMarker.selectedCollisionRect(
            at: selectedAnchorPoint,
            badges: selectedStation.routeBadges
        )

        for station in orderedStations where station.id != selectedStation.id {
            guard let currentVisibility = visibilityByID[station.id],
                  let anchorPoint = projectedMapPoint(for: station.coordinate) else {
                continue
            }

            let markerCollisionRect = BusStopMarker.markerCollisionRect(
                at: anchorPoint,
                isSelected: false
            )
            let showsMarker = !markerCollisionRect.intersects(selectedCollisionRect)

            let showsInlineLabels: Bool
            if let inlineLabelRect = BusStopMarker.inlineLabelCollisionRect(
                at: anchorPoint,
                badges: station.routeBadges
            ) {
                showsInlineLabels = currentVisibility.showsInlineLabels
                    && !inlineLabelRect.intersects(selectedCollisionRect)
                    && showsMarker
            } else {
                showsInlineLabels = false
            }

            visibilityByID[station.id] = StationAnnotationVisibility(
                showsMarker: showsMarker,
                showsInlineLabels: showsInlineLabels
            )
        }

        return visibilityByID
    }

    private func wantsInlineLabels(for station: BusAPI.Station) -> Bool {
        shouldShowStationLabels
        && !station.routeBadges.isEmpty
        && station.id != presentedStation?.id
    }

    private func cancelLineDetailTask() {
        lineDetailLoadTask?.cancel()
        lineDetailLoadTask = nil
    }

    private func mapRegion(for stations: [BusAPI.Station]) -> MKCoordinateRegion {
        let latitudes = stations.map(\.latitude)
        let longitudes = stations.map(\.longitude)

        let minLatitude = latitudes.min() ?? 31.018
        let maxLatitude = latitudes.max() ?? 31.043
        let minLongitude = longitudes.min() ?? 121.422
        let maxLongitude = longitudes.max() ?? 121.448

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        let latitudeDelta = max((maxLatitude - minLatitude) * 1.45, 0.012)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.35, 0.014)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private func mapRegion(
        for coordinates: [CLLocationCoordinate2D],
        fallbackCenter: CLLocationCoordinate2D,
        minimumSpan: MKCoordinateSpan,
        fitToVisibleArea: Bool = false
    ) -> MKCoordinateRegion {
        let bottomObstructionFraction = fitToVisibleArea
        ? currentMapBottomObstructionFraction
        : 0
        let centerShiftFraction = fitToVisibleArea
        ? max(
            bottomObstructionFraction / 2 - currentMapCenterDownwardCompensationFraction,
            0
        )
        : 0
        let visibleHeightFraction = max(1 - bottomObstructionFraction, 0.001)

        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: fallbackCenter.latitude
                    - minimumSpan.latitudeDelta * centerShiftFraction,
                    longitude: fallbackCenter.longitude
                ),
                span: minimumSpan
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let minLatitude = latitudes.min() ?? fallbackCenter.latitude
        let maxLatitude = latitudes.max() ?? fallbackCenter.latitude
        let minLongitude = longitudes.min() ?? fallbackCenter.longitude
        let maxLongitude = longitudes.max() ?? fallbackCenter.longitude

        let latitudeFactor = fitToVisibleArea
        ? max(1.35, 1 / visibleHeightFraction)
        : 1.35
        let latitudeDelta = max(
            (maxLatitude - minLatitude) * latitudeFactor,
            minimumSpan.latitudeDelta
        )
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.35, minimumSpan.longitudeDelta)
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2
            - latitudeDelta * centerShiftFraction,
            longitude: (minLongitude + maxLongitude) / 2
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private func sheetOverlapHeight(
        for sheetFrame: CGRect
    ) -> CGFloat {
        guard !sheetFrame.isEmpty, !mapViewFrame.isEmpty else {
            return 0
        }

        let overlap = mapViewFrame.intersection(sheetFrame)
        guard !overlap.isNull else {
            return 0
        }

        return max(overlap.height, 0)
    }

    private func refocusPresentedLineDetailIfNeeded(
        animated: Bool = true
    ) {
        guard let selection = presentedLineDetail,
              let cachedData = viewModel.lineDetailState(for: selection).cachedData else {
            return
        }

        focusOnLineDetail(
            cachedData,
            selection: selection,
            animated: animated
        )
    }

    private func projectedMapPoint(
        for coordinate: CLLocationCoordinate2D
    ) -> CGPoint? {
        guard let visibleRegion,
              mapViewSize.width > 0,
              mapViewSize.height > 0,
              visibleRegion.span.latitudeDelta > 0,
              visibleRegion.span.longitudeDelta > 0 else {
            return nil
        }

        let minLongitude = visibleRegion.center.longitude - visibleRegion.span.longitudeDelta / 2
        let maxLatitude = visibleRegion.center.latitude + visibleRegion.span.latitudeDelta / 2
        let xFraction = (coordinate.longitude - minLongitude) / visibleRegion.span.longitudeDelta
        let yFraction = (maxLatitude - coordinate.latitude) / visibleRegion.span.latitudeDelta

        return CGPoint(
            x: CGFloat(xFraction) * mapViewSize.width,
            y: CGFloat(yFraction) * mapViewSize.height
        )
    }
}
