import Foundation
import Testing
@testable import DynamicNotch

@Suite struct HomeApplianceTests {
    /// La lavasecadora Hisense WDSE1214 a media lavada (datos reales de ConnectLife, recortados)
    static let washingStatus: [String: String] = [
        "machine_status": "2", "Current_program_phase": "3", "Selected_program_ID": "7",
        "Selected_program_remaining_time_in_minutes": "113", "Selected_program_total_time_in_minutes": "130",
        "temperature": "4", "Spin_speed_rpm": "10", "Door_status": "3", "error_code": "0", "dry_time": "0",
    ]

    @Test func washerMidCycle() {
        let washer = WasherStatus(name: "Lavadora", model: "WDSE1214-MVB005-000", isOnline: true, status: Self.washingStatus)
        #expect(washer.machine == .running)
        #expect(washer.phase == .wash)
        #expect(washer.isCycleActive)
        #expect(washer.program == "Algodón")
        #expect(washer.temperature == "40°")
        #expect(washer.spin == "1000 rpm")
        #expect(!washer.isDoorOpen)
        #expect(!washer.hasError)
        #expect(abs(washer.progress - 17.0 / 130.0) < 0.0001)
        #expect(washer.timeline == [.wash, .rinse, .spin])
    }

    @Test func washerFinishedOrOfflineIsNotActive() {
        var status = Self.washingStatus
        status["Current_program_phase"] = "10"
        #expect(!WasherStatus(name: "", model: "", isOnline: true, status: status).isCycleActive)
        #expect(!WasherStatus(name: "", model: "", isOnline: false, status: Self.washingStatus).isCycleActive)
        status["machine_status"] = "3"
        status["Current_program_phase"] = "4"
        let paused = WasherStatus(name: "", model: "", isOnline: true, status: status)
        #expect(paused.isCycleActive)
        #expect(paused.statusTitle == "En pausa")
    }

    @Test func washerErrorAndDryingProgram() {
        var status = Self.washingStatus
        status["error_code"] = "5"
        let washer = WasherStatus(name: "", model: "", isOnline: true, status: status)
        #expect(washer.hasError)
        #expect(washer.statusTitle == "Error F05")
        status["error_code"] = "0"
        status["Selected_program_ID"] = "1"
        #expect(WasherStatus(name: "", model: "", isOnline: true, status: status).timeline.last == .dry)
    }

    @Test func fridgeTemperaturesSkipMissingSensors() {
        let fridge = FridgeStatus(name: "Refri", model: "BCD-668WP1NWF1R1/HC1(H)", isOnline: true, status: [
            "refrigerator_temperature": "4", "refrigerator_real_temperature": "8",
            "freeze_temperature": "-14", "freeze_real_temperature": "-17",
            "environment_real_temperature": "26", "variation_temperature": "-40",
            "open_the_door_alarm": "0", "open_freeze_door_alarm": "1", "sf_mode": "0", "sr_mode": "1",
        ])
        #expect(fridge.fridgeTarget == 4)
        #expect(fridge.fridgeActual == 8)
        #expect(fridge.freezerTarget == -14)
        #expect(fridge.freezerActual == -17)
        #expect(fridge.ambient == 26)
        #expect(fridge.isFreezerDoorAlarm && !fridge.isFridgeDoorAlarm)
        #expect(fridge.superCool && !fridge.superFreeze)
        let noSensor = FridgeStatus(name: "", model: "", isOnline: true, status: ["freeze_real_temperature": "-40"])
        #expect(noSensor.freezerActual == nil)
    }

    @Test func fridgeDoorOpenWithoutAlarm() {
        let open = FridgeStatus(name: "", model: "", isOnline: true, status: ["refr_room_open": "1", "open_the_door_alarm": "0"])
        #expect(open.isFridgeDoorOpen && !open.isDoorAlarm && open.isDoorOpen)
        let freezer = FridgeStatus(name: "", model: "", isOnline: true, status: ["free_room_open": "1"])
        #expect(freezer.isFreezerDoorOpen && !freezer.isFridgeDoorOpen)
        let closed = FridgeStatus(name: "", model: "", isOnline: true, status: ["refr_room_open": "0", "free_room_open": "0"])
        #expect(!closed.isDoorOpen)
    }

    @Test func snapshotSortsAppliancesByType() {
        let raw: [[String: Any]] = [
            ["deviceId": "a", "deviceTypeCode": "025", "deviceNickName": "Lavadora", "offlineState": 1,
             "statusList": ["machine_status": "2", "Current_program_phase": 3]],
            ["deviceId": "b", "deviceTypeCode": "026", "deviceNickName": "Refri", "offlineState": 0,
             "statusList": ["refrigerator_temperature": "4"]],
            ["deviceId": "c", "deviceTypeCode": "009", "deviceNickName": "Clima"],
            ["deviceNickName": "Sin id"],
        ]
        let snapshot = HomeSnapshot(appliances: raw.compactMap(ConnectLifeClient.parseAppliance))
        #expect(snapshot.washers.count == 1)
        #expect(snapshot.washers[0].phase == .wash)
        #expect(snapshot.fridges.count == 1)
        #expect(!snapshot.fridges[0].isOnline)
    }

    /// Lo que se firma tiene que ser idéntico a lo de la librería de Python (connectlife 0.14.0)
    @Test func gatewaySigningStringMatchesPythonLibrary() throws {
        let params: [String: String] = [
            "accessToken": "tok", "appId": ConnectLifeClient.gatewayAppId, "appSecret": ConnectLifeClient.gatewayAppSecret,
            "languageId": "12", "randStr": "00112233445566778899aabbccddeeff", "timeStamp": "1700000000000",
            "timezone": "1.0", "version": "5.0", "sign": "se ignora",
        ]
        #expect(ConnectLifeClient.signingString(params) ==
            "accessToken=tok&appId=47110565134383&appSecret=yOzhz6junYno-nmULM3Wr7PU_dpSZN22ZdluvVWZ4uW5ZwwG8fIGCHTbrhcnU-iv&languageId=12&randStr=00112233445566778899aabbccddeeff&timeStamp=1700000000000&timezone=1.0&version=5.0D9519A4B756946F081B7BB5B5E8D1197")
        // La firma RSA sale (256 bytes en base64) y se escapa en la URL
        let signed = try ConnectLifeClient.signedGatewayParameters(accessToken: "tok", payload: [:])
        let sign = try #require(signed["sign"])
        #expect(Data(base64Encoded: sign)?.count == 256)
        let query = ConnectLifeClient.formEncode(["sign": "a+b/c="])
        #expect(query == "sign=a%2Bb%2Fc%3D")
    }

    /// Un comando se firma con `properties` como JSON compacto, igual que la librería de Python
    @Test func commandSigningStringMatchesPythonLibrary() throws {
        var params: [String: String] = [
            "accessToken": "tok", "appId": ConnectLifeClient.gatewayAppId, "appSecret": ConnectLifeClient.gatewayAppSecret,
            "languageId": "12", "randStr": "00112233445566778899aabbccddeeff", "timeStamp": "1700000000000",
            "timezone": "1.0", "version": "5.0", "puid": "p1",
        ]
        params["properties"] = try ConnectLifeClient.compactJSON(["SET_REFRIGERATOR_TEMPERATURE": "5"])
        #expect(ConnectLifeClient.signingString(params) ==
            "accessToken=tok&appId=47110565134383&appSecret=yOzhz6junYno-nmULM3Wr7PU_dpSZN22ZdluvVWZ4uW5ZwwG8fIGCHTbrhcnU-iv&languageId=12&properties={\"SET_REFRIGERATOR_TEMPERATURE\":\"5\"}&puid=p1&randStr=00112233445566778899aabbccddeeff&timeStamp=1700000000000&timezone=1.0&version=5.0D9519A4B756946F081B7BB5B5E8D1197")
    }

    @Test func fridgeControlsAndRanges() {
        #expect(FridgeControl.fridgeTemperature(5).command == ("SET_REFRIGERATOR_TEMPERATURE", "5"))
        #expect(FridgeControl.freezerTemperature(-18).command == ("SET_FREEZE_TEMPERATURE", "-18"))
        #expect(FridgeControl.superCool(true).command == ("SET_SR_MODE", "1"))
        #expect(FridgeControl.superFreeze(false).command == ("SET_SF_MODE", "0"))
        #expect(FridgeControl.eco(true).statusKey == "save_mode")
        // Los rangos del propio refri (los de tu modelo: 2…9 y −24…−13)
        let fridge = FridgeStatus(name: "", model: "", isOnline: true, status: [
            "refrigerator_min_temperature": "2", "refrigerator_max_temperature": "9",
            "freeze_min_temperature": "-24", "freeze_max_temperature": "-13",
            "existing_sr_mode": "1", "existing_sf_mode": "1", "existing_save_mode": "0", "save_mode": "0",
        ])
        #expect(fridge.fridgeRange == 2...9)
        #expect(fridge.freezerRange == -24...(-13))
        #expect(fridge.supportsSuperCool && !fridge.supportsEco)
        // Sin datos: los de connectlife-ha
        let bare = FridgeStatus(name: "", model: "", isOnline: true, status: [:])
        #expect(bare.fridgeRange == 0...8)
        #expect(HomeStore.sameValue("5", "5.0") && !HomeStore.sameValue("5", "6"))
    }

    /// Flujo completo contra el servidor de prueba de la librería de Python:
    /// `CONNECTLIFE_TEST_SERVER=http://127.0.0.1:8080 ./scripts/test.sh --filter HomeApplianceTests`
    @Test func fullFlowAgainstTestServer() async throws {
        guard let server = ProcessInfo.processInfo.environment["CONNECTLIFE_TEST_SERVER"] else { return }
        let client = ConnectLifeClient(username: "prueba@example.com", password: "x", endpoints: .testServer(server))
        try await client.login()
        let appliances = try await client.appliances()
        let snapshot = HomeSnapshot(appliances: appliances)
        #expect(!snapshot.washers.isEmpty)
        #expect(!snapshot.fridges.isEmpty)
        #expect(snapshot.washers[0].remainingMinutes == 113)

        // Un comando: el servidor de prueba (scratchpad/cl_mock_server.py) lo aplica como el aparato
        let fridge = snapshot.fridges[0]
        let six = FridgeControl.fridgeTemperature(6).command
        try await client.update(puid: fridge.puid, properties: [six.name: six.value])
        let after = HomeSnapshot(appliances: try await client.appliances())
        #expect(after.fridges[0].fridgeTarget == 6)
        let four = FridgeControl.fridgeTemperature(4).command
        try await client.update(puid: fridge.puid, properties: [four.name: four.value])
    }
}
