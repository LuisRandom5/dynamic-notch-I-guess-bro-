import Foundation
import Testing
@testable import DynamicNotch

@Suite struct CalendarMeetingTests {
    @Test func recognizesVideoCallServices() {
        #expect(CalendarActivityProvider.serviceName(for: URL(string: "https://us02web.zoom.us/j/123")!) == "Zoom")
        #expect(CalendarActivityProvider.serviceName(for: URL(string: "https://meet.google.com/abc-defg-hij")!) == "Meet")
        #expect(CalendarActivityProvider.serviceName(for: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!) == "Teams")
        #expect(CalendarActivityProvider.serviceName(for: URL(string: "https://example.com/meet")!) == nil)
    }

    @Test func findsTheLinkInNotes() {
        let notes = "Agenda: diseño\nÚnete: https://meet.google.com/abc-defg-hij\nOtra: https://example.com"
        #expect(CalendarActivityProvider.meetingURL(inText: notes)?.host == "meet.google.com")
        #expect(CalendarActivityProvider.meetingURL(inText: "Sala 3, piso 2") == nil)
    }
}
