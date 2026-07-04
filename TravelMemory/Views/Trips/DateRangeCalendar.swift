//
//  DateRangeCalendar.swift
//  TravelMemory
//
//  A unified date range calendar where users tap to select
//  start date, then end date, with the range visually highlighted.
//

import SwiftUI

struct DateRangeCalendar: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var onRangeSelected: (() -> Void)?
    
    @State private var displayedMonth: Date
    @State private var selectionPhase: SelectionPhase = .selectingStart
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    
    enum SelectionPhase {
        case selectingStart
        case selectingEnd
    }
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, onRangeSelected: (() -> Void)? = nil) {
        _startDate = startDate
        _endDate = endDate
        _displayedMonth = State(initialValue: startDate.wrappedValue)
        self.onRangeSelected = onRangeSelected
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            monthHeader
            
            // Day of week headers
            dayOfWeekHeaders
            
            // Calendar grid
            calendarGrid
        }
    }
    
    // MARK: - Month Header
    
    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Color.voyagerSurfaceContainerHigh)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text(monthYearString(from: displayedMonth))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.voyagerOnSurface)
            
            Spacer()
            
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Color.voyagerSurfaceContainerHigh)
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Day of Week Headers
    
    private var dayOfWeekHeaders: some View {
        HStack(spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
    }
    
    // MARK: - Day Cell
    
    private func dayCell(_ date: Date) -> some View {
        let isStart = calendar.isDate(date, inSameDayAs: startDate)
        let isEnd = calendar.isDate(date, inSameDayAs: endDate)
        let isInRange = date > startDate && date < endDate
        let isToday = calendar.isDateInToday(date)
        let isPast = date < calendar.startOfDay(for: Date()) && !isToday
        
        return Button {
            selectDate(date)
        } label: {
            ZStack {
                // Range background - stretches across the cell
                if isInRange {
                    Rectangle()
                        .fill(Color.voyagerPrimaryAccent.opacity(0.15))
                        .frame(height: 36)
                }
                
                // Start date - right half range bg
                if isStart && !calendar.isDate(startDate, inSameDayAs: endDate) {
                    HStack(spacing: 0) {
                        Color.clear
                        Rectangle()
                            .fill(Color.voyagerPrimaryAccent.opacity(0.15))
                    }
                    .frame(height: 36)
                }
                
                // End date - left half range bg
                if isEnd && !calendar.isDate(startDate, inSameDayAs: endDate) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.voyagerPrimaryAccent.opacity(0.15))
                        Color.clear
                    }
                    .frame(height: 36)
                }
                
                // Circle for start/end
                if isStart || isEnd {
                    Circle()
                        .fill(Color.voyagerPrimaryAccent)
                        .frame(width: 36, height: 36)
                }
                
                // Today ring
                if isToday && !isStart && !isEnd {
                    Circle()
                        .stroke(Color.voyagerPrimary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                }
                
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isStart || isEnd ? .bold : isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isStart || isEnd ? .white :
                        isPast ? Color.voyagerOnSurfaceVariant.opacity(0.4) :
                        isInRange ? Color.voyagerPrimaryAccent :
                        Color.voyagerOnSurface
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(height: 38)
        .disabled(isPast && selectionPhase == .selectingStart)
    }
    
    // MARK: - Selection Logic
    
    private func selectDate(_ date: Date) {
        switch selectionPhase {
        case .selectingStart:
            startDate = date
            if endDate <= date {
                endDate = date
            }
            withAnimation(.easeOut(duration: 0.2)) {
                selectionPhase = .selectingEnd
            }
            
        case .selectingEnd:
            if date < startDate {
                // If they pick before start, reset and start over
                startDate = date
                endDate = date
            } else {
                endDate = date
                withAnimation(.easeOut(duration: 0.2)) {
                    selectionPhase = .selectingStart
                }
                onRangeSelected?()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1 // 0-indexed
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        // Pad to fill last row
        let remainder = days.count % 7
        if remainder > 0 {
            days.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }
        
        return days
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
