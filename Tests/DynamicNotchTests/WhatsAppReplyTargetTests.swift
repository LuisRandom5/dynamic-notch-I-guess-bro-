import Foundation
import Testing
@testable import DynamicNotch

/// La respuesta desde la isla va al chat de quien escribió, nunca al que esté abierto
@Suite struct WhatsAppReplyTargetTests {
    @Test func namesMatchIgnoringAccentsCaseAndInvisibleMarks() {
        #expect(WhatsAppWebObserverService.chatNamesMatch("José Pérez", "jose perez"))
        #expect(WhatsAppWebObserverService.chatNamesMatch("\u{200E}Ana  López\u{200F}", "Ana López"))
        #expect(WhatsAppWebObserverService.chatNamesMatch("+52 1 229 208 4039", "+52 1 229 208 4039"))
    }

    @Test func differentPeopleDoNotMatch() {
        #expect(!WhatsAppWebObserverService.chatNamesMatch("Ana", "Mariana"))
        #expect(!WhatsAppWebObserverService.chatNamesMatch("Ana López", "Ana"))
        #expect(!WhatsAppWebObserverService.chatNamesMatch("", ""))
    }

    @Test func demoSendersAreMarkedNotGuessedByName() {
        #expect(!DemoMessages.isDemo("Carlos Real"))
        DemoMessages.mark("Contacto de prueba")
        #expect(DemoMessages.isDemo("contacto de prueba"))
    }

    @Test func scriptsEscapeQuotesAndCheckTheOpenChat() {
        let scripts = WhatsAppWebObserverService.replyScripts(message: "Hola 'tú'\nok", recipient: "O'Brien")
        #expect(scripts.open.contains("norm('O\\'Brien')"))
        #expect(scripts.send.contains("return 'WRONG_CHAT'"))
        #expect(scripts.send.contains("Hola \\'tú\\'\\nok"))
        // Para probarlos en una página de prueba (ver docs): DN_WRITE_REPLY_JS=1
        if ProcessInfo.processInfo.environment["DN_WRITE_REPLY_JS"] != nil {
            try? scripts.open.write(toFile: "/tmp/dn_reply_open.js", atomically: true, encoding: .utf8)
            try? scripts.send.write(toFile: "/tmp/dn_reply_send.js", atomically: true, encoding: .utf8)
        }
    }
}
