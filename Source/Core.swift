import AppKit
import Carbon
import Security
import ScreenCaptureKit

struct AppFailure: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ s:String) { message=s } }
enum Provider: String, Codable, CaseIterable {
    case openAI = "OpenAI", groq = "Groq", gemini = "Google Gemini", mistral = "Mistral", openRouter = "OpenRouter"
    var endpoint: String { switch self {
    case .openAI: return "https://api.openai.com/v1/responses"
    case .groq: return "https://api.groq.com/openai/v1/chat/completions"
    case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    case .mistral: return "https://api.mistral.ai/v1/chat/completions"
    case .openRouter: return "https://openrouter.ai/api/v1/chat/completions"
    } }
    // Model IDs recovered from the supplied 0.4.6 binary; account availability varies.
    var models: [String] { switch self {
    case .openAI: return ["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"]
    case .groq: return ["qwen/qwen3.8-27b"]
    case .gemini: return ["gemini-3.8-flash"]
    case .mistral: return ["ministral-14b-2512", "ministral-8b-2512"]
    case .openRouter: return ["qwen/qwen3.8-27b:free"]
    } }
}
enum ResponseMode: String, Codable, CaseIterable {
    case brief = "Кратко", steps = "Объяснить по шагам", translate = "Перевести на английский", summarize = "Суммировать", custom = "Своя инструкция"
    func instruction(_ custom: String) -> String { switch self {
    case .brief: return "Answer each requested question briefly. Output only the answer. Reply in the user's language."
    case .steps: return "Answer the requested task and explain the solution in clear numbered steps. Reply in the user's language."
    case .translate: return "Translate the requested visible or supplied content into English. Output only the translation."
    case .summarize: return "Summarize the requested content in a few concise bullet points. Reply in the user's language."
    case .custom: return custom
    } }
}
struct Shortcut: Codable, Equatable {
    var key: UInt32; var modifiers: UInt32; var label: String
    static let defaults: [Shortcut] = [
        .init(key:49,modifiers:UInt32(controlKey|shiftKey),label:"⌃⇧Space"),
        .init(key:44,modifiers:UInt32(controlKey),label:"⌃/"),
        .init(key:17,modifiers:UInt32(controlKey|optionKey),label:"⌃⌥T"),
        .init(key:1,modifiers:UInt32(controlKey|optionKey),label:"⌃⌥S"),
        .init(key:12,modifiers:UInt32(controlKey|optionKey),label:"⌃⌥Q"),
        .init(key:51,modifiers:UInt32(controlKey),label:"⌃⌫")]
    static let names = ["Снимок и ответ", "Показать / скрыть", "Тест захвата", "Настройки", "Выход", "Ввести вопрос"]
}
struct Settings: Codable {
    var provider: Provider = .openAI
    var modelByProvider: [String:[String]] = [:]
    var mode: ResponseMode = .brief
    var customInstruction = ""
    var fontSize: Double = 17
    var transparency: Double = 12
    var textOpacity: Double = 100
    var background = "#1A202C"
    var foreground = "#EFF2F7"
    var accent = "#354052"
    var shortcuts = Shortcut.defaults
    var cropQuestion = true
    var showCommands = true
    var answerModel: String { modelByProvider[provider.rawValue]?.first ?? provider.models[0] }
    var visionModel: String { modelByProvider[provider.rawValue]?.last ?? provider.models[0] }
    static var url: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScreenCompanionMac/settings.json") }
    static func load() -> Settings { guard let d=try? Data(contentsOf:url), let s=try? JSONDecoder().decode(Self.self,from:d), s.shortcuts.count==6 else { return .init() }; return s }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories:true)
        try JSONEncoder().encode(self).write(to:Self.url,options:.atomic)
    }
}
enum KeyVault {
    static let service = "local.screencompanion.macos.api"
    static func query(_ p:Provider) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:p.rawValue] }
    static func read(_ p:Provider) throws -> String {
        var q=query(p); q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?; let s=SecItemCopyMatching(q as CFDictionary,&result)
        if s == errSecItemNotFound { return "" }
        guard s == errSecSuccess,let d=result as? Data,let v=String(data:d,encoding:.utf8) else { throw AppFailure("Не удалось прочитать ключ из Связки ключей (\(s)).") }; return v
    }
    static func save(_ key:String, for p:Provider) throws {
        let q=query(p)
        if key.isEmpty { let s=SecItemDelete(q as CFDictionary); guard s==errSecSuccess || s==errSecItemNotFound else { throw AppFailure("Не удалось удалить ключ (\(s)).") }; return }
        let value=[kSecValueData as String:Data(key.utf8)]
        var s=SecItemUpdate(q as CFDictionary,value as CFDictionary)
        if s == errSecItemNotFound { var item=q; item.merge(value){_,n in n}; item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly; s=SecItemAdd(item as CFDictionary,nil) }
        guard s==errSecSuccess else { throw AppFailure("Не удалось сохранить ключ в Связке ключей (\(s)).") }
    }
}
struct Region: Codable {
    let x:Double; let y:Double; let width:Double; let height:Double
    func rect(in image:CGImage) throws -> CGRect {
        guard [x,y,width,height].allSatisfy({$0.isFinite}),x>=0,y>=0,width>0,height>0,x+width<=1.001,y+height<=1.001 else { throw AppFailure("Модель вернула неверную область снимка. Попробуй отключить обрезку в настройках.") }
        let pad=0.015; let x0=max(0,x-pad); let y0=max(0,y-pad)
        return CGRect(x:x0*Double(image.width),y:y0*Double(image.height),width:(min(1,x+width+pad)-x0)*Double(image.width),height:(min(1,y+height+pad)-y0)*Double(image.height)).integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
    }
}
struct Detection: Codable { let found:Bool; let region:Region? }
enum ScreenCapture {
    @MainActor static func capture() async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { throw AppFailure("Разреши запись экрана для ScreenCompanion в Системных настройках → Конфиденциальность и безопасность → Запись экрана. Затем перезапусти приложение.") }
        let mouse=NSEvent.mouseLocation
        let screen=NSScreen.screens.first(where:{$0.frame.contains(mouse)}) ?? NSScreen.main
        let id=(screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let display=content.displays.first(where:{$0.displayID==id}) ?? content.displays.first else { throw AppFailure("Доступный экран не найден.") }
        let own=content.applications.filter({$0.processID == ProcessInfo.processInfo.processIdentifier})
        let filter=SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config=SCStreamConfiguration(); let scale=min(1.0,2400.0/Double(max(display.width,display.height)))
        config.width=max(1,Int(Double(display.width)*scale)); config.height=max(1,Int(Double(display.height)*scale)); config.showsCursor=false
        return try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
    }
    static func jpeg(_ image:CGImage) throws -> Data {
        guard let d=NSBitmapImageRep(cgImage:image).representation(using:.jpeg,properties:[.compressionFactor:0.86]) else { throw AppFailure("Не удалось подготовить снимок.") }; return d
    }
}
struct ModelClient {
    let provider:Provider; let key:String
    static func body(provider:Provider,model:String,instruction:String,text:String,images:[Data],schema:[String:Any]?=nil) -> [String:Any] {
        if provider == .openAI {
            var content:[[String:Any]]=[["type":"input_text","text":text]]
            content += images.map {["type":"input_image","image_url":"data:image/jpeg;base64,"+$0.base64EncodedString(),"detail":"high"]}
            var b:[String:Any] = ["model":model,"store":false,"max_output_tokens":8000,"input":[["role":"developer","content":instruction],["role":"user","content":content]]]
            if let schema { b["text"]=["format":["type":"json_schema","name":"screencompanion","strict":true,"schema":schema]] }; return b
        }
        var content:[[String:Any]]=[["type":"text","text":text]]
        content += images.map {["type":"image_url","image_url":["url":"data:image/jpeg;base64,"+$0.base64EncodedString()]]}
        var b:[String:Any] = ["model":model,"stream":false,"messages":[["role":"system","content":instruction],["role":"user","content":content]]]
        b[provider == .groq ? "max_completion_tokens" : "max_tokens"]=8000
        if let schema { b["response_format"]=["type":"json_schema","json_schema":["name":"screencompanion","strict":true,"schema":schema]] }
        if provider == .openRouter { b["provider"]=["require_parameters":true,"data_collection":"deny"] }; return b
    }
    static func parse(_ obj:[String:Any], provider:Provider) throws -> String {
        if provider == .openAI {
            if obj["status"] as? String == "incomplete" { throw AppFailure("Ответ модели не завершён. Попробуй меньшую область или другую модель.") }
            let output=obj["output"] as? [[String:Any]] ?? []; var result:[String]=[]
            for item in output { for part in item["content"] as? [[String:Any]] ?? [] {
                if part["type"] as? String == "refusal" { throw AppFailure(part["refusal"] as? String ?? "Сервис отклонил запрос.") }
                if part["type"] as? String == "output_text",let text=part["text"] as? String { result.append(text) }
            } }
            let text=result.joined(separator:"\n"); guard !text.isEmpty else { throw AppFailure("Сервис вернул пустой ответ.") }; return text
        }
        guard let choice=(obj["choices"] as? [[String:Any]])?.first,let message=choice["message"] as? [String:Any] else { throw AppFailure("Не удалось прочитать ответ сервиса.") }
        if let refusal=message["refusal"] as? String,!refusal.isEmpty { throw AppFailure(refusal) }
        if ["length","content_filter"].contains(choice["finish_reason"] as? String ?? "") { throw AppFailure("Сервис не завершил ответ: \(choice["finish_reason"] ?? "").") }
        if let s=message["content"] as? String,!s.isEmpty { return s }
        if let parts=message["content"] as? [[String:Any]] { let s=parts.compactMap{$0["text"] as? String}.joined(separator:"\n"); if !s.isEmpty { return s } }
        throw AppFailure("Сервис вернул пустой ответ. Проверь модель и доступ к ней.")
    }
    func request(model:String,instruction:String,text:String,images:[Data]=[],schema:[String:Any]?=nil) async throws -> String {
        var req=URLRequest(url:URL(string:provider.endpoint)!); req.httpMethod="POST"; req.timeoutInterval=120
        req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONSerialization.data(withJSONObject:Self.body(provider:provider,model:model,instruction:instruction,text:text,images:images,schema:schema))
        let (data,response)=try await URLSession.shared.data(for:req)
        guard let response=response as? HTTPURLResponse else { throw AppFailure("Нет ответа от сервиса.") }
        guard (200..<300).contains(response.statusCode) else {
            // Do not log response bodies, keys, screenshots, or questions.
            let hint: String
            switch response.statusCode { case 401,403: hint="Проверь API-ключ и доступ к выбранной модели."; case 404: hint="Проверь точный ID модели."; case 429: hint="Проверь баланс и лимиты API; повтори позже."; case 400,422: hint="Модель должна поддерживать изображения и структурированные ответы. Проверь ID обеих моделей."; default: hint="Повтори позже или выбери другой сервис." }
            throw AppFailure("\(provider.rawValue): HTTP \(response.statusCode). \(hint)")
        }
        guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AppFailure("Сервис вернул неверный формат.") }; return try Self.parse(obj,provider:provider)
    }
}
let regionSchema: [String:Any] = ["type":"object","properties":["found":["type":"boolean"],"region":["anyOf":[["type":"null"],["type":"object","properties":["x":["type":"number"],"y":["type":"number"],"width":["type":"number"],"height":["type":"number"]],"required":["x","y","width","height"],"additionalProperties":false]]]],"required":["found","region"],"additionalProperties":false]

@MainActor final class Hotkeys {
    var refs:[EventHotKeyRef]=[]; var handler:EventHandlerRef?; var action:((Int)->Void)?
    init() {
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,event,user in
            guard let event,let user else{return OSStatus(eventNotHandledErr)}
            var id=EventHotKeyID(); GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            let host=Unmanaged<Hotkeys>.fromOpaque(user).takeUnretainedValue()
            MainActor.assumeIsolated { host.action?(Int(id.id)) }; return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func install(_ shortcuts:[Shortcut]) throws {
        guard Set(shortcuts.map{"\($0.key):\($0.modifiers)"}).count==shortcuts.count else { throw AppFailure("Для каждой команды нужна отдельная комбинация.") }
        clear()
        for (i,s) in shortcuts.enumerated() {
            var ref:EventHotKeyRef?; let status=RegisterEventHotKey(s.key,s.modifiers,EventHotKeyID(signature:0x53434D43,id:UInt32(i)),GetApplicationEventTarget(),0,&ref)
            guard status==noErr,let ref else { clear();throw AppFailure("Комбинация \(s.label) занята или недоступна. Выбери другую.") }; refs.append(ref)
        }
    }
    func clear() { refs.forEach{UnregisterEventHotKey($0)};refs=[] }
}
