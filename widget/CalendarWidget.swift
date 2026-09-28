// 나의 캘린더 - 홈 화면 위젯 3종
//  ① 오늘 · 내일 (중간 4×2)  ② 이번 주 (중간 4×2)  ③ 이번 달 + 오늘 (큰 4×4)
// 아이폰 캘린더(일정)와 미리알림(할 일)을 직접 읽어서 보여줌. 누르면 앱이 열림.
// 위젯 길게 누르기 → 위젯 편집: 보여줄 항목(일정+할 일 / 일정만 / 할 일만), 한 주의 시작(일/월)

import WidgetKit
import SwiftUI
import EventKit
import AppIntents
import UIKit

// MARK: - 위젯 설정

enum ShowMode: String, AppEnum {
    case all, events, todos
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "보여줄 항목"
    static var caseDisplayRepresentations: [ShowMode: DisplayRepresentation] = [
        .all: "일정 + 할 일",
        .events: "일정만",
        .todos: "할 일만",
    ]
}

enum WeekStart: String, AppEnum {
    case sunday, monday
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "한 주의 시작"
    static var caseDisplayRepresentations: [WeekStart: DisplayRepresentation] = [
        .sunday: "일요일",
        .monday: "월요일",
    ]
}

struct CalConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "위젯 설정"
    static var description = IntentDescription("위젯에 보여줄 항목과 한 주의 시작 요일을 고르세요.")

    @Parameter(title: "보여줄 항목", default: .all)
    var show: ShowMode

    @Parameter(title: "한 주의 시작", default: .sunday)
    var weekStart: WeekStart
}

// MARK: - 데이터

struct RGB: Hashable {
    var r: Double
    var g: Double
    var b: Double
}

struct Item: Hashable {
    let title: String
    let time: String?      // 시간 일정만 "07:00", 종일 일정·할 일은 nil
    let rgb: RGB
    let isTodo: Bool
    let sortKey: String
}

struct CalEntry: TimelineEntry {
    let date: Date
    let days: [String: [Item]]
    let access: Bool
    let weekStart: Int     // Calendar weekday 기준: 1 = 일요일, 2 = 월요일

    func items(_ d: Date) -> [Item] { days[dayKey(d)] ?? [] }
}

let kCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "ko_KR")
    c.timeZone = .current
    return c
}()

func dayKey(_ d: Date) -> String {
    let c = kCal.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

func fmt(_ d: Date, _ format: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.calendar = kCal
    f.timeZone = .current
    f.dateFormat = format
    return f.string(from: d)
}

func rgb(of cg: CGColor?) -> RGB {
    guard let cg = cg else { return RGB(r: 0.5, g: 0.5, b: 0.5) }
    let ui = UIColor(cgColor: cg)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
        return RGB(r: Double(r), g: Double(g), b: Double(b))
    }
    var w: CGFloat = 0
    _ = ui.getWhite(&w, alpha: &a)
    return RGB(r: Double(w), g: Double(w), b: Double(w))
}

// MARK: - 색 보정 (앱과 같은 규칙: 라이트에서 너무 연한 색은 같은 색감으로 진하게, 다크에서 너무 어두운 색은 밝게)

func relLum(_ c: RGB) -> Double {
    func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
}

func toHSL(_ c: RGB) -> (Double, Double, Double) {
    let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
    let l = (mx + mn) / 2, d = mx - mn
    if d == 0 { return (0, 0, l) }
    let s = d / (1 - abs(2 * l - 1))
    var h: Double
    if mx == c.r { h = ((c.g - c.b) / d + 6).truncatingRemainder(dividingBy: 6) }
    else if mx == c.g { h = (c.b - c.r) / d + 2 }
    else { h = (c.r - c.g) / d + 4 }
    h *= 60
    return (h, s, l)
}

func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> RGB {
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    var r = 0.0, g = 0.0, b = 0.0
    if h < 60 { r = c; g = x }
    else if h < 120 { r = x; g = c }
    else if h < 180 { g = c; b = x }
    else if h < 240 { g = x; b = c }
    else if h < 300 { r = x; b = c }
    else { r = c; b = x }
    return RGB(r: min(max(r + m, 0), 1), g: min(max(g + m, 0), 1), b: min(max(b + m, 0), 1))
}

func visibleColor(_ c: RGB, dark: Bool) -> Color {
    let lum = relLum(c)
    let needsFix = dark ? lum < 0.06 : lum > 0.6
    if !needsFix { return Color(red: c.r, green: c.g, blue: c.b) }
    var (h, s, l) = toHSL(c)
    if s > 0.15 { s = max(s, 0.65) }
    if !dark && h >= 46 && h <= 72 { h = 42 }   // 노랑은 어두워지면 올리브빛 → 골드 쪽으로
    for _ in 0..<60 {
        let o = fromHSL(h, s, min(max(l, 0), 1))
        let L = relLum(o)
        if dark ? L >= 0.1 : L <= 0.45 { return Color(red: o.r, green: o.g, blue: o.b) }
        l += dark ? 0.02 : -0.02
    }
    let o = fromHSL(h, s, min(max(l, 0), 1))
    return Color(red: o.r, green: o.g, blue: o.b)
}

// MARK: - 아이폰 캘린더 · 미리알림 읽기

func hasAccess(_ type: EKEntityType) -> Bool {
    let s = EKEventStore.authorizationStatus(for: type)
    return s == .fullAccess || s == .authorized
}

func loadEntry(_ config: CalConfigIntent) async -> CalEntry {
    let store = EKEventStore()
    let now = Date()
    let today = kCal.startOfDay(for: now)
    let monthStart = kCal.date(from: kCal.dateComponents([.year, .month], from: today)) ?? today
    // 이번 달 달력(앞뒤 주 포함) + 이번 주 + 내일까지 넉넉히
    let from = kCal.date(byAdding: .day, value: -7, to: min(monthStart, today)) ?? today
    let to = kCal.date(byAdding: .day, value: 50, to: monthStart) ?? today

    var days: [String: [Item]] = [:]
    let evOK = hasAccess(.event), remOK = hasAccess(.reminder)
    let mode = config.show

    if mode != .todos && evOK {
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        for ev in store.events(matching: pred) {
            guard let start = ev.startDate, let end = ev.endDate else { continue }
            let color = rgb(of: ev.calendar?.cgColor)
            let title = ev.title ?? "(제목 없음)"
            var d = kCal.startOfDay(for: start)
            let last = kCal.startOfDay(for: max(start, end.addingTimeInterval(-1)))
            var first = true
            while d <= last {   // 여러 날에 걸친 일정은 날마다 표시
                let time: String? = (ev.isAllDay || !first) ? nil : fmt(start, "HH:mm")
                let key = (time == nil ? "0" : "1" + fmt(start, "HHmm")) + title
                days[dayKey(d), default: []].append(Item(title: title, time: time, rgb: color, isTodo: false, sortKey: key))
                first = false
                guard let next = kCal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
    }

    if mode != .events && remOK {
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: from, ending: to, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            _ = store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        for r in reminders {
            guard let dc = r.dueDateComponents, let due = kCal.date(from: dc) else { continue }
            let title = r.title ?? "(제목 없음)"
            days[dayKey(due), default: []].append(Item(title: title, time: nil, rgb: rgb(of: r.calendar?.cgColor), isTodo: true, sortKey: "2" + title))
        }
    }

    for k in days.keys { days[k]?.sort { $0.sortKey < $1.sortKey } }  // 종일 → 시간순 일정 → 할 일
    let access = mode == .todos ? remOK : (mode == .events ? evOK : (evOK || remOK))
    return CalEntry(date: now, days: days, access: access, weekStart: config.weekStart == .monday ? 2 : 1)
}

extension CalEntry {
    static var sample: CalEntry {
        let t = kCal.startOfDay(for: Date())
        let tomorrow = kCal.date(byAdding: .day, value: 1, to: t) ?? t
        let blue = RGB(r: 0.23, g: 0.51, b: 0.96), green = RGB(r: 0.13, g: 0.77, b: 0.37)
        let pink = RGB(r: 0.93, g: 0.28, b: 0.6), orange = RGB(r: 0.98, g: 0.45, b: 0.09)
        var days: [String: [Item]] = [:]
        days[dayKey(t)] = [
            Item(title: "헬스", time: "07:00", rgb: green, isTodo: false, sortKey: "1"),
            Item(title: "발레", time: "11:30", rgb: pink, isTodo: false, sortKey: "2"),
            Item(title: "자소서 제출", time: nil, rgb: orange, isTodo: true, sortKey: "3"),
        ]
        days[dayKey(tomorrow)] = [Item(title: "친구 약속", time: "19:00", rgb: blue, isTodo: false, sortKey: "1")]
        return CalEntry(date: Date(), days: days, access: true, weekStart: 1)
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CalEntry { .sample }

    func snapshot(for configuration: CalConfigIntent, in context: Context) async -> CalEntry {
        if context.isPreview { return .sample }
        return await loadEntry(configuration)
    }

    func timeline(for configuration: CalConfigIntent, in context: Context) async -> Timeline<CalEntry> {
        let entry = await loadEntry(configuration)
        let now = Date()
        let midnight = kCal.startOfDay(for: kCal.date(byAdding: .day, value: 1, to: now) ?? now)
        // 30분마다, 그리고 자정이 지나면 새로 그림 (앱에서 나갈 때도 앱이 새로 고침을 요청)
        let next = min(now.addingTimeInterval(30 * 60), midnight.addingTimeInterval(5))
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - 공통 화면 조각

struct ItemRow: View {
    let item: Item
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let c = visibleColor(item.rgb, dark: scheme == .dark)
        HStack(spacing: 5) {
            if item.isTodo {
                RoundedRectangle(cornerRadius: 2.5).stroke(c, lineWidth: 1.5).frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3, height: 13)
            }
            if let t = item.time {
                Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(item.title).font(.system(size: 12)).lineLimit(1)
        }
    }
}

struct DayColumn: View {
    let title: String
    let items: [Item]
    let highlight: Bool
    let maxRows: Int

    var body: some View {
        let show = items.count > maxRows ? Array(items.prefix(maxRows - 1)) : items
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlight ? Color.red : Color.secondary)
            if items.isEmpty {
                Text("일정 없음").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            ForEach(Array(show.enumerated()), id: \.offset) { _, it in
                ItemRow(item: it)
            }
            if items.count > show.count {
                Text("+\(items.count - show.count)개 더").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoAccessView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 20))
            Text("앱을 열어 캘린더·미리알림\n접근을 허용해 주세요")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ① 오늘 · 내일

struct TodayTomorrowView: View {
    let entry: CalEntry

    var body: some View {
        if !entry.access {
            NoAccessView()
        } else {
            let today = kCal.startOfDay(for: entry.date)
            let tomorrow = kCal.date(byAdding: .day, value: 1, to: today) ?? today
            HStack(alignment: .top, spacing: 12) {
                DayColumn(title: "오늘 " + fmt(today, "M/d E"), items: entry.items(today), highlight: true, maxRows: 5)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5)
                DayColumn(title: "내일 " + fmt(tomorrow, "M/d E"), items: entry.items(tomorrow), highlight: false, maxRows: 5)
            }
        }
    }
}

// MARK: - ② 이번 주

struct WeekView: View {
    let entry: CalEntry
    @Environment(\.colorScheme) var scheme

    var body: some View {
        if !entry.access {
            NoAccessView()
        } else {
            let today = kCal.startOfDay(for: entry.date)
            let wd = kCal.component(.weekday, from: today)
            let start = kCal.date(byAdding: .day, value: -((wd - entry.weekStart + 7) % 7), to: today) ?? today
            let days = (0..<7).map { kCal.date(byAdding: .day, value: $0, to: start) ?? start }
            VStack(alignment: .leading, spacing: 4) {
                Text(fmt(days[0], "M/d") + " – " + fmt(days[6], "M/d"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
                HStack(alignment: .top, spacing: 3) {
                    ForEach(days, id: \.self) { d in
                        dayCell(d, today: today)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    func dayCell(_ d: Date, today: Date) -> some View {
        let items = entry.items(d)
        let wd = kCal.component(.weekday, from: d)
        let isToday = d == today
        let show = items.count > 3 ? Array(items.prefix(2)) : items
        VStack(spacing: 2) {
            Text(fmt(d, "E"))
                .font(.system(size: 10))
                .foregroundStyle(wd == 1 ? Color.red : (wd == 7 ? Color.blue : Color.secondary))
            ZStack {
                if isToday {
                    Circle().fill(Color.red).frame(width: 20, height: 20)
                }
                Text("\(kCal.component(.day, from: d))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
            }
            .frame(height: 20)
            ForEach(Array(show.enumerated()), id: \.offset) { _, it in
                let c = visibleColor(it.rgb, dark: scheme == .dark)
                Text(it.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity)
                    .background(c.opacity(it.isTodo ? 0.1 : 0.25))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(it.isTodo ? c : Color.clear, lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if items.count > show.count {
                Text("+\(items.count - show.count)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ③ 이번 달 + 오늘

struct MonthView: View {
    let entry: CalEntry
    @Environment(\.colorScheme) var scheme

    var body: some View {
        if !entry.access {
            NoAccessView()
        } else {
            let today = kCal.startOfDay(for: entry.date)
            let monthStart = kCal.date(from: kCal.dateComponents([.year, .month], from: today)) ?? today
            let lead = (kCal.component(.weekday, from: monthStart) - entry.weekStart + 7) % 7
            let gridStart = kCal.date(byAdding: .day, value: -lead, to: monthStart) ?? monthStart
            let dayCount = kCal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            let rows = (lead + dayCount + 6) / 7
            let month = kCal.component(.month, from: monthStart)
            let order = (0..<7).map { (entry.weekStart - 1 + $0) % 7 + 1 }
            VStack(alignment: .leading, spacing: 3) {
                Text(fmt(today, "yyyy년 M월"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.red)
                HStack(spacing: 0) {
                    ForEach(order, id: \.self) { w in
                        Text(kCal.shortWeekdaySymbols[w - 1])
                            .font(.system(size: 10))
                            .foregroundStyle(w == 1 ? Color.red : (w == 7 ? Color.blue : Color.secondary))
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { c in
                                monthCell(kCal.date(byAdding: .day, value: r * 7 + c, to: gridStart) ?? gridStart, month: month, today: today)
                            }
                        }
                    }
                }
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 0.5).padding(.vertical, 3)
                todayList(today)
                Spacer(minLength: 0)
            }
        }
    }

    func dotColors(_ items: [Item]) -> [RGB] {
        var seen: [RGB] = []
        for it in items where !seen.contains(it.rgb) {
            seen.append(it.rgb)
            if seen.count == 3 { break }
        }
        return seen
    }

    @ViewBuilder
    func monthCell(_ d: Date, month: Int, today: Date) -> some View {
        let items = entry.items(d)
        let wd = kCal.component(.weekday, from: d)
        let out = kCal.component(.month, from: d) != month
        let isToday = d == today
        let dots = dotColors(items)
        VStack(spacing: 1) {
            ZStack {
                if isToday {
                    Circle().fill(Color.red).frame(width: 18, height: 18)
                }
                Text("\(kCal.component(.day, from: d))")
                    .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.white : (out ? Color.secondary.opacity(0.5) : (wd == 1 ? Color.red : (wd == 7 ? Color.blue : Color.primary))))
            }
            .frame(height: 18)
            HStack(spacing: 2) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                    Circle().fill(visibleColor(c, dark: scheme == .dark)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 5)
            .opacity(out ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }

    @ViewBuilder
    func todayList(_ today: Date) -> some View {
        let items = entry.items(today)
        let show = items.count > 4 ? Array(items.prefix(3)) : items
        let half = (show.count + 1) / 2
        let left = Array(show.prefix(half))
        let right = Array(show.dropFirst(half))
        VStack(alignment: .leading, spacing: 3) {
            Text("오늘 " + fmt(today, "M/d E"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
            if items.isEmpty {
                Text("일정 없음").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(left.enumerated()), id: \.offset) { _, it in ItemRow(item: it) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(right.enumerated()), id: \.offset) { _, it in ItemRow(item: it) }
                    if items.count > show.count {
                        Text("+\(items.count - show.count)개 더").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 위젯 등록

struct TodayTomorrowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayTomorrow", intent: CalConfigIntent.self, provider: Provider()) { entry in
            TodayTomorrowView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("오늘 · 내일")
        .description("오늘과 내일의 일정과 할 일")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ThisWeek", intent: CalConfigIntent.self, provider: Provider()) { entry in
            WeekView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("이번 주")
        .description("이번 주 일정과 할 일")
        .supportedFamilies([.systemMedium])
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ThisMonth", intent: CalConfigIntent.self, provider: Provider()) { entry in
            MonthView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("이번 달")
        .description("이번 달 달력과 오늘 일정")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct CalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTomorrowWidget()
        WeekWidget()
        MonthWidget()
    }
}
