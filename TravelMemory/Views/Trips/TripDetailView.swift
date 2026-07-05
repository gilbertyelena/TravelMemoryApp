//
//  TripDetailView.swift
//  TravelMemory
//
//  Shows a single trip's full itinerary as a unified
//  chronological timeline with day markers and a "Today" line.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Timeline Entry (unified wrapper)

struct TimelineEntry: Identifiable {
    let id = UUID()
    let date: Date
    let kind: TimelineEntryKind
}

enum TimelineEntryKind {
    case flight(FlightSegment)
    case hotel(HotelBooking)
    case car(CarRentalBooking)
    case dining(DiningReservation)
    case activity(TripActivity)
    
    var sortDate: Date {
        switch self {
        case .flight(let f): return f.departureTime
        case .hotel(let h): return h.checkInDate
        case .car(let c): return c.pickupTime
        case .dining(let d): return d.reservationTime
        case .activity(let a): return a.startTime
        }
    }
}

// MARK: - Trip Detail View

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    
    @State private var showEditTrip = false
    @State private var showAddItem = false
    @State private var editingFlight: FlightSegment?
    @State private var editingHotel: HotelBooking?
    @State private var editingCar: CarRentalBooking?
    @State private var editingDining: DiningReservation?
    @State private var editingActivity: TripActivity?
    @State private var showDeleteConfirm = false
    @State private var appeared = false
    @AppStorage("tripViewMode") private var agendaMode = false
    @State private var shareItems: [Any]?
    /// IDs of freshly created (draft) items — deleted again if their
    /// editor is dismissed without saving.
    @State private var newItemIDs: Set<UUID> = []
    
    /// All items merged and sorted chronologically
    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for f in trip.flights { entries.append(TimelineEntry(date: f.departureTime, kind: .flight(f))) }
        for h in trip.hotels { entries.append(TimelineEntry(date: h.checkInDate, kind: .hotel(h))) }
        for c in trip.carRentals { entries.append(TimelineEntry(date: c.pickupTime, kind: .car(c))) }
        for d in trip.dining { entries.append(TimelineEntry(date: d.reservationTime, kind: .dining(d))) }
        for a in trip.activities { entries.append(TimelineEntry(date: a.startTime, kind: .activity(a))) }
        return entries.sorted { $0.date < $1.date }
    }
    
    /// Group entries by calendar day
    private var groupedByDay: [(key: Date, entries: [TimelineEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: timelineEntries) { cal.startOfDay(for: $0.date) }
        return grouped.map { (key: $0.key, entries: $0.value) }
            .sorted { $0.key < $1.key }
    }
    
    private let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
    
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                    // Trip header
                    tripHeader
                    
                    if !conflicts.isEmpty {
                        conflictBanner
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                    }

                    // ━━ UNIFIED TIMELINE / AGENDA ━━
                    if timelineEntries.isEmpty {
                        emptyTimeline
                    } else if agendaMode {
                        TripAgendaView(trip: trip, onEdit: edit(item:))
                    } else {
                        unifiedTimeline
                    }
                    
                    // Free evenings — nudge toward dinner plans
                    if trip.status != .completed && !freeEvenings.isEmpty && !timelineEntries.isEmpty {
                        freeEveningsSection
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                    }

                    // Packing List
                    packingSection
                        .padding(.horizontal, VoyagerSpacing.marginMain)
                        .staggeredAppear(index: groupedByDay.count + 2, appeared: appeared)
                    
                    // Delete trip
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("DELETE TRIP")
                        }
                        .font(VoyagerFont.labelCaps)
                        .tracking(0.6)
                        .foregroundStyle(Color.voyagerError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.voyagerError.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.top, 8)
                }
                .padding(.bottom, 160)
            }
            
            // Floating Add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showAddItem = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.voyagerPrimaryAccent)
                            .clipShape(Circle())
                            .shadow(color: Color.voyagerPrimaryAccent.opacity(0.4), radius: 12, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(trip.name)
                    .font(VoyagerFont.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        shareItems = [TripExporter.plainText(for: trip)]
                    } label: {
                        Label("Share as Text", systemImage: "text.alignleft")
                    }
                    Button {
                        if let url = TripExporter.pdfFile(for: trip) { shareItems = [url] }
                    } label: {
                        Label("Share PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        if let url = TripExporter.icsFile(for: trip) { shareItems = [url] }
                    } label: {
                        Label("Share Calendar (.ics)", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.voyagerPrimary)
                }
                .accessibilityLabel("Export itinerary")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { agendaMode.toggle() }
                } label: {
                    Image(systemName: agendaMode ? "calendar.day.timeline.left" : "list.bullet.rectangle")
                        .foregroundStyle(Color.voyagerPrimary)
                }
                .accessibilityLabel(agendaMode ? "Show timeline" : "Show agenda")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditTrip = true } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
        }
        .sheet(isPresented: $showEditTrip) {
            EditTripView(mode: .edit(trip))
        }
        .sheet(isPresented: $showAddItem) {
            AddItemSheet(
                trip: trip,
                onFlightCreated: { flight in
                    newItemIDs.insert(flight.id)
                    editingFlight = flight
                },
                onHotelCreated: { hotel in
                    newItemIDs.insert(hotel.id)
                    editingHotel = hotel
                },
                onCarCreated: { car in
                    newItemIDs.insert(car.id)
                    editingCar = car
                },
                onActivityCreated: { activity in
                    newItemIDs.insert(activity.id)
                    editingActivity = activity
                },
                onDiningCreated: { dining in
                    newItemIDs.insert(dining.id)
                    editingDining = dining
                }
            )
        }
        .sheet(item: $editingFlight, onDismiss: { newItemIDs.removeAll() }) { flight in
            EditFlightView(
                flight: flight,
                isNew: newItemIDs.contains(flight.id),
                onSaveAndAddReturn: { returnFlight in
                    // Insert the id after the sheet's onDismiss has cleared
                    // the set, or the return draft loses its "new" status.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        newItemIDs.insert(returnFlight.id)
                        editingFlight = returnFlight
                    }
                }
            )
        }
        .sheet(item: $editingHotel, onDismiss: { newItemIDs.removeAll() }) { hotel in
            EditHotelView(hotel: hotel, isNew: newItemIDs.contains(hotel.id))
        }
        .sheet(item: $editingCar, onDismiss: { newItemIDs.removeAll() }) { car in
            EditCarView(car: car, isNew: newItemIDs.contains(car.id))
        }
        .sheet(item: $editingDining, onDismiss: { newItemIDs.removeAll() }) { dining in
            EditDiningView(reservation: dining, isNew: newItemIDs.contains(dining.id))
        }
        .sheet(item: $editingActivity, onDismiss: { newItemIDs.removeAll() }) { activity in
            EditActivityView(activity: activity, isNew: newItemIDs.contains(activity.id))
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let items = shareItems {
                ShareSheet(items: items)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Delete Trip?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(trip)
                modelContext.saveOrLog()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(trip.name)\" and all its items.")
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }
    
    // MARK: - Conflicts

    /// Pairs of items whose time spans overlap (hotels and car rentals
    /// span days by nature, so they are excluded).
    private var conflicts: [(a: any ItineraryItem, b: any ItineraryItem)] {
        let items = trip.timelineItems.filter { !($0 is HotelBooking) && !($0 is CarRentalBooking) }
        var found: [(any ItineraryItem, any ItineraryItem)] = []
        for i in items.indices {
            for j in items.indices where j > i {
                if items[i].occupiedInterval.intersects(items[j].occupiedInterval) {
                    found.append((items[i], items[j]))
                }
            }
        }
        return found
    }

    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text("SCHEDULE CONFLICT\(conflicts.count == 1 ? "" : "S")")
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.8)
            }
            .foregroundStyle(Color.voyagerTertiary)

            ForEach(Array(conflicts.prefix(3).enumerated()), id: \.offset) { _, pair in
                Text("\(pair.a.agendaTitle) overlaps \(pair.b.agendaTitle)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyagerTertiary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                .stroke(Color.voyagerTertiary.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Routes an agenda row tap to the right editor sheet
    private func edit(item: any ItineraryItem) {
        switch item {
        case let flight as FlightSegment: editingFlight = flight
        case let hotel as HotelBooking: editingHotel = hotel
        case let car as CarRentalBooking: editingCar = car
        case let dining as DiningReservation: editingDining = dining
        case let activity as TripActivity: editingActivity = activity
        default: break
        }
    }

    // MARK: - Free Evenings

    /// Trip days with no dining plans yet
    private var freeEvenings: [Date] {
        let cal = Calendar.current
        let diningDays = Set(trip.dining.map { cal.startOfDay(for: $0.reservationTime) })
        var days: [Date] = []
        var day = cal.startOfDay(for: trip.startDate)
        let end = cal.startOfDay(for: trip.endDate)
        var guardCounter = 0
        while day <= end && guardCounter < 60 {
            if !diningDays.contains(day) { days.append(day) }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCounter += 1
        }
        return days
    }

    private var freeEveningsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#FFB868"))
                Text("EVENINGS WITHOUT DINNER PLANS")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(freeEvenings.prefix(10), id: \.self) { day in
                        Button {
                            planDinner(on: day)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 11))
                                Text(dayFmt.string(from: day))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color(hex: "#FFB868"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#FFB868").opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .voyagerCard()
    }

    /// Creates a dinner draft for the chosen evening and opens the editor
    /// (with its restaurant search and map browser).
    private func planDinner(on day: Date) {
        let evening = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: day) ?? day
        let dining = DiningReservation(reservationTime: evening)
        dining.status = .idea
        dining.trip = trip
        modelContext.insert(dining)
        newItemIDs.insert(dining.id)
        editingDining = dining
    }

    // MARK: - Trip Header
    
    private var tripHeader: some View {
        let gradientColors = DestinationGradient.colors(
            for: trip.destination.isEmpty ? trip.name : trip.destination
        )
        
        return VStack(alignment: .leading, spacing: 8) {
            // Gradient accent bar
            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(Capsule())
                .padding(.bottom, 4)
            
            Text(trip.destination.isEmpty ? trip.name : trip.destination)
                .font(VoyagerFont.headlineLarge)
                .foregroundStyle(Color.voyagerOnBackground)
            
            Text("\(trip.dateRangeText) • \(trip.durationDays) Day\(trip.durationDays == 1 ? "" : "s")")
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)

            if !trip.budgetText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 12))
                    Text(trip.budgetText)
                        .font(VoyagerFont.bodyMedium)
                }
                .foregroundStyle(Color.voyagerTertiary)
            }
            
            // Status pills
            HStack(spacing: 12) {
                ForEach(TripStatus.allCases, id: \.rawValue) { status in
                    Button {
                        trip.status = status
                        modelContext.saveOrLog()
                    } label: {
                        Text(status.rawValue.uppercased())
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                            .foregroundStyle(trip.status == status ? .white : Color.voyagerOnSurfaceVariant)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(trip.status == status ? statusColor(status) : Color.voyagerSurfaceContainerHigh)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
        .padding(.top, 8)
    }
    
    // MARK: - Unified Timeline
    
    private var unifiedTimeline: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groupedByDay.enumerated()), id: \.element.key) { dayIdx, group in
                let isToday = Calendar.current.isDate(group.key, inSameDayAs: Date())
                let isPast = group.key < todayStart
                
                // ━━ Day Header ━━
                HStack(spacing: 10) {
                    // Timeline node
                    ZStack {
                        Circle()
                            .fill(isToday ? Color.voyagerPrimaryAccent : (isPast ? Color.voyagerSurfaceVariant : Color.voyagerPrimary))
                            .frame(width: 10, height: 10)
                        
                        if isToday {
                            Circle()
                                .stroke(Color.voyagerPrimaryAccent.opacity(0.3), lineWidth: 2)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(dayFmt.string(from: group.key).uppercased())
                                .font(VoyagerFont.labelCaps)
                                .tracking(1.0)
                                .foregroundStyle(isToday ? Color.voyagerPrimaryAccent : Color.voyagerOnSurfaceVariant)
                            
                            if isToday {
                                Text("TODAY")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.voyagerPrimaryAccent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, VoyagerSpacing.marginMain)
                .padding(.top, dayIdx == 0 ? 0 : 20)
                .padding(.bottom, 10)
                .staggeredAppear(index: dayIdx, appeared: appeared)
                
                // ━━ Items for this day ━━
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { entryIdx, entry in
                    HStack(alignment: .top, spacing: 0) {
                        // Vertical spine
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.voyagerTimelineSpine)
                                .frame(width: 2)
                        }
                        .frame(width: 20)
                        .padding(.leading, 16)
                        
                        // Card
                        Group {
                            switch entry.kind {
                            case .flight(let flight):
                                flightTimelineCard(flight)
                            case .hotel(let hotel):
                                hotelTimelineCard(hotel)
                            case .car(let car):
                                carTimelineCard(car)
                            case .dining(let dining):
                                diningTimelineCard(dining)
                            case .activity(let activity):
                                activityTimelineCard(activity)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                    }
                    .staggeredAppear(index: dayIdx + entryIdx + 1, appeared: appeared)
                }
            }
        }
    }
    
    // MARK: - Flight Timeline Card
    
    private func flightTimelineCard(_ flight: FlightSegment) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        
        return Button { editingFlight = flight } label: {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane.departure")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerPrimaryAccent)
                        Text(flight.airlineAndFlight.uppercased())
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    ItemStatusBadge(status: flight.status)
                    Spacer()
                    Text(timeFmt.string(from: flight.departureTime))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.voyagerPrimary)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flight.departureAirport)
                            .font(VoyagerFont.headlineMedium)
                        Text(flight.departureCity)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.voyagerOutlineVariant)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(flight.arrivalAirport)
                            .font(VoyagerFont.headlineMedium)
                        Text(flight.arrivalCity)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                .foregroundStyle(Color.voyagerOnSurface)
                
                if !flight.confirmationCode.isEmpty || !flight.gate.isEmpty {
                    HStack {
                        if !flight.gate.isEmpty {
                            Text("GATE \(flight.gate)")
                                .font(VoyagerFont.labelCaps)
                                .foregroundStyle(Color.voyagerOnSurface)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.voyagerSurfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        if !flight.confirmationCode.isEmpty {
                            Text("Ref: \(flight.confirmationCode)")
                                .font(VoyagerFont.labelCaps)
                                .foregroundStyle(Color.voyagerPrimary)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Hotel Timeline Card
    
    private func hotelTimelineCard(_ hotel: HotelBooking) -> some View {
        let fmt = DateFormatter()
        let _ = fmt.dateFormat = "MMM d"
        
        return Button { editingHotel = hotel } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "bed.double")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerTertiary)
                        Text("CHECK-IN • \(hotel.nightsCount) NIGHT\(hotel.nightsCount == 1 ? "" : "S")")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    ItemStatusBadge(status: hotel.status)
                    Spacer()
                }
                
                Text(hotel.hotelName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text("\(fmt.string(from: hotel.checkInDate)) → \(fmt.string(from: hotel.checkOutDate))")
                }
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                
                if !hotel.confirmationCode.isEmpty {
                    Text("Ref: \(hotel.confirmationCode)")
                        .font(VoyagerFont.labelCaps)
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Car Timeline Card
    
    private func carTimelineCard(_ car: CarRentalBooking) -> some View {
        let fmt = DateFormatter()
        let _ = fmt.dateFormat = "MMM d, HH:mm"
        
        return Button { editingCar = car } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "car")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerPrimary)
                        Text("CAR PICKUP")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    ItemStatusBadge(status: car.status)
                    Spacer()
                    if car.isPrepaid {
                        Text("PRE-PAID")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                            .foregroundStyle(Color.voyagerTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.voyagerTertiary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                Text(car.company)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                if !car.vehicleType.isEmpty {
                    Text(car.vehicleType)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Text("\(fmt.string(from: car.pickupTime)) → \(fmt.string(from: car.dropoffTime))")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Dining Timeline Card
    
    private func diningTimelineCard(_ dining: DiningReservation) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        
        return Button { editingDining = dining } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#FFB868"))
                        Text("DINING")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    ItemStatusBadge(status: dining.status)
                    Spacer()
                    Text(timeFmt.string(from: dining.reservationTime))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FFB868"))
                }
                
                Text(dining.restaurantName.isEmpty ? "Restaurant" : dining.restaurantName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                HStack(spacing: 12) {
                    if dining.partySize > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 11))
                            Text("\(dining.partySize)")
                                .font(VoyagerFont.bodySmall)
                        }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    
                    if !dining.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                            Text(dining.address)
                                .font(VoyagerFont.bodySmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                
                if !dining.confirmationCode.isEmpty {
                    Text("Ref: \(dining.confirmationCode)")
                        .font(VoyagerFont.labelCaps)
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color(hex: "#FFB868").opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Activity Timeline Card
    
    private func activityTimelineCard(_ activity: TripActivity) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        let catColor = Color(hex: activity.category.color)
        
        return Button { editingActivity = activity } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: activity.category.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(catColor)
                        Text(activity.category.label.uppercased())
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    ItemStatusBadge(status: activity.status)
                    Spacer()
                    Text(timeFmt.string(from: activity.startTime))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(catColor)
                }
                
                Text(activity.activityName.isEmpty ? "Activity" : activity.activityName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                HStack(spacing: 12) {
                    if !activity.provider.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2")
                                .font(.system(size: 11))
                            Text(activity.provider)
                                .font(VoyagerFont.bodySmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    
                    if !activity.location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                            Text(activity.location)
                                .font(VoyagerFont.bodySmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                
                HStack {
                    if !activity.priceInfo.isEmpty {
                        Text(activity.priceInfo)
                            .font(VoyagerFont.labelCaps)
                            .foregroundStyle(catColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(catColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    if !activity.confirmationCode.isEmpty {
                        Text("Ref: \(activity.confirmationCode)")
                            .font(VoyagerFont.labelCaps)
                            .foregroundStyle(Color.voyagerPrimary)
                    }
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(catColor.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty Timeline
    
    private var emptyTimeline: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.4))
            Text("No itinerary items yet")
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            Text("Tap the + button to add flights,\naccommodation, dining, or activities")
                .font(.system(size: 13))
                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Packing Section
    
    private var packingSection: some View {
        let totalItems = trip.packingCategories.flatMap(\.items).count
        let packedItems = trip.packingCategories.flatMap(\.items).filter(\.isPacked).count
        let progress = totalItems > 0 ? Double(packedItems) / Double(totalItems) : 0
        
        return NavigationLink {
            PackingListView(trip: trip)
        } label: {
            HStack(spacing: 14) {
                PackingProgressRing(progress: progress, size: 44, lineWidth: 3)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Packing List")
                        .font(VoyagerFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    
                    if totalItems > 0 {
                        Text("\(packedItems)/\(totalItems) items packed")
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    } else {
                        Text("Tap to start your packing list")
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.voyagerOutlineVariant)
            }
            .padding(14)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func statusColor(_ status: TripStatus) -> Color {
        switch status {
        case .planning: return Color.voyagerPrimary
        case .live: return Color.voyagerPrimaryAccent
        case .completed: return Color.voyagerTertiary
        }
    }
}

// MARK: - Add Item Sheet

struct AddItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    var onFlightCreated: ((FlightSegment) -> Void)?
    var onHotelCreated: ((HotelBooking) -> Void)?
    var onCarCreated: ((CarRentalBooking) -> Void)?
    var onActivityCreated: ((TripActivity) -> Void)?
    var onDiningCreated: ((DiningReservation) -> Void)?
    @State private var showPasteImport = false
    @State private var showFilePicker = false
    @State private var showCSVPicker = false
    @State private var icsParseResult: EmailParser.ParseResult?
    @State private var icsFileName = ""
    @State private var showICSResult = false
    @State private var icsImportError: String?

    /// UTTypes accepted by the calendar file picker
    private var calendarFileTypes: [UTType] {
        var types: [UTType] = []
        if let ics = UTType(filenameExtension: "ics") { types.append(ics) }
        if let mime = UTType(mimeType: "text/calendar") { types.append(mime) }
        return types.isEmpty ? [.data] : types
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()

                VStack(spacing: VoyagerSpacing.stackMedium) {
                    Text("Add to Trip")
                        .font(VoyagerFont.headlineMedium)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .padding(.top, 24)

                    addButton(icon: "doc.on.clipboard", title: "Paste Booking Confirmation", subtitle: "Import every flight, hotel & car from one email") {
                        showPasteImport = true
                    }

                    addButton(icon: "calendar.badge.plus", title: "Import Calendar File", subtitle: "Exact import from an .ics \"Add to calendar\" file") {
                        showFilePicker = true
                    }

                    addButton(icon: "tablecells", title: "Import Spreadsheet (CSV)", subtitle: "Migrate an itinerary you keep in Excel or Sheets") {
                        showCSVPicker = true
                    }

                    if let importError = icsImportError {
                        Text(importError)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider().background(Color.voyagerOutlineVariant.opacity(0.3))
                    
                    addButton(icon: "airplane.departure", title: "Flight", subtitle: "Add a flight segment") {
                        let flight = FlightSegment(
                            airline: "", flightNumber: "",
                            departureAirport: "", departureCity: "",
                            arrivalAirport: "", arrivalCity: "",
                            departureTime: trip.startDate,
                            arrivalTime: trip.startDate
                        )
                        flight.trip = trip
                        modelContext.insert(flight)
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onFlightCreated?(flight)
                        }
                    }

                    addButton(icon: "bed.double", title: "Accommodation", subtitle: "Add a hotel, apartment, or B&B") {
                        let hotel = HotelBooking(
                            hotelName: "",
                            checkInDate: trip.startDate,
                            checkOutDate: trip.endDate
                        )
                        hotel.trip = trip
                        modelContext.insert(hotel)
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onHotelCreated?(hotel)
                        }
                    }

                    addButton(icon: "car", title: "Car Rental", subtitle: "Add a car rental booking") {
                        let car = CarRentalBooking(
                            company: "",
                            pickupTime: trip.startDate,
                            dropoffTime: trip.endDate
                        )
                        car.trip = trip
                        modelContext.insert(car)
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onCarCreated?(car)
                        }
                    }
                    
                    addButton(icon: "fork.knife", title: "Restaurant", subtitle: "Add a dining reservation") {
                        let dining = DiningReservation(
                            reservationTime: trip.startDate
                        )
                        dining.trip = trip
                        modelContext.insert(dining)
                        modelContext.saveOrLog()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onDiningCreated?(dining)
                        }
                    }
                    
                    addButton(icon: "figure.hiking", title: "Activity", subtitle: "Diving, boat trip, tour, and more") {
                        let activity = TripActivity(
                            startTime: trip.startDate,
                            endTime: trip.startDate
                        )
                        activity.trip = trip
                        modelContext.insert(activity)
                        modelContext.saveOrLog()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onActivityCreated?(activity)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, VoyagerSpacing.marginMain)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .sheet(isPresented: $showPasteImport) {
                EmailInputView(targetTrip: trip, onCommitted: { dismiss() })
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: calendarFileTypes) { pickResult in
                icsImportError = nil
                switch pickResult {
                case .success(let url):
                    importCalendarFile(at: url)
                case .failure(let error):
                    icsImportError = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $showCSVPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { pickResult in
                icsImportError = nil
                switch pickResult {
                case .success(let url):
                    importSpreadsheet(at: url)
                case .failure(let error):
                    icsImportError = error.localizedDescription
                }
            }
            .sheet(isPresented: $showICSResult) {
                if let result = icsParseResult {
                    ParseResultView(
                        result: result,
                        onAccept: {
                            let service = EmailIngestionService(modelContext: modelContext)
                            service.commit(result, subject: icsFileName, body: "", sender: "", into: trip)
                            showICSResult = false
                            dismiss()
                        },
                        onDiscard: {
                            showICSResult = false
                        }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func importSpreadsheet(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            icsImportError = "Could not read \(url.lastPathComponent)"
            return
        }

        icsFileName = url.lastPathComponent
        icsParseResult = CSVImporter.parse(text)
        showICSResult = true
    }

    private func importCalendarFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            icsImportError = "Could not read \(url.lastPathComponent)"
            return
        }
        guard ICSParser.isCalendar(text) else {
            icsImportError = "\(url.lastPathComponent) is not a calendar file"
            return
        }

        icsFileName = url.lastPathComponent
        icsParseResult = ICSParser.parse(text)
        showICSResult = true
    }

    private func addButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.voyagerPrimary)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VoyagerFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(subtitle)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.voyagerPrimary)
            }
            .padding(16)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
