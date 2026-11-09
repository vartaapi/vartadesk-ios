import UIKit

/** One message as the chat shows it. "me" is the person using the app. */
struct DeskMessage: Equatable {
    var id: String
    var fromMe: Bool
    var type: String
    var body: String?
    var mediaFilename: String?
    var createdAt: String
    var mediaUrl: String? = nil
    var mediaMime: String? = nil
    var pending = false
    var failed: String? = nil
}

/** One of the person's tickets (DK7). label: the business's own word for where it is. */
struct DeskTicket: Equatable {
    var ref: String
    var subject: String
    var details: String?
    var status: String
    var label: String?
    var updatedAt: String

    /** "Ticket #12", or the business's own reference. */
    var name: String { ref.allSatisfy(\.isNumber) ? "Ticket #\(ref)" : ref }

    /** Where it is, in the business's words if it has its own. */
    var statusWords: String {
        if let label { return label }
        switch status {
        case "waiting": return "Waiting on you"
        case "resolved": return "Resolved"
        default: return "Open"
        }
    }
}

/** A help article in a list: enough to show its title and open it. */
struct DeskArticleItem: Equatable {
    var slug: String
    var title: String
    var summary: String
}

/** How the business's chat looks, from /config and /session. */
struct DeskLook {
    var name: String
    var color: UIColor
    var greeting: String
    var intro: String
    var reply: String
    var open: Bool
    var backAt: String?
    var ticketForm: Bool
    var helpArticles: Int
    var branding: Bool
}

/** A screen of the kit (or the chat button) that redraws when anything changes. */
@MainActor
protocol DeskListener: AnyObject {
    func deskChanged()
    func deskError(_ message: String)
}

/**
 * Talks to the same public chat API the website widget uses
 * (/desk/v1/:workspace/…), as the app. Everything the screens show lives
 * here, so every screen of the kit shares one conversation. Listeners are
 * always called on the main thread.
 *
 * The live stream stays open while anything is listening and the person has
 * chatted before; nothing listening, no connection.
 */
@MainActor
final class DeskClient {
    let workspace: String
    private let apiBase: String
    private let prefs = UserDefaults.standard
    private let http: URLSession

    private var user: VartaDeskUser?
    private var token: String?
    private var stream: DeskStream?
    private var retry: TimeInterval = 1
    private var tempIds = 0
    private var sessionAt: Date?
    private var listeners: [ObjectIdentifier: Weak] = [:]

    private(set) var look: DeskLook?
    private(set) var messages: [DeskMessage] = []
    private(set) var tickets: [DeskTicket] = []
    private(set) var email: String?
    private(set) var started = false
    private(set) var closed = false
    private(set) var verified = false
    private(set) var teamTyping: String?
    private(set) var loading = false
    /** The chat screen is showing: replies arriving now are seen, not unread. */
    var chatVisible = false

    init(workspace: String, apiBase: String) {
        self.workspace = workspace
        self.apiBase = apiBase
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = false
        http = URLSession(configuration: cfg)
        token = prefs.string(forKey: key("token"))
    }

    private func key(_ name: String) -> String { "vartadesk.\(workspace).\(name)" }

    /** Team replies the person hasn't seen in the chat yet. */
    var unread: Int {
        let seen = prefs.string(forKey: key("seenAt")) ?? ""
        return messages.filter { !$0.fromMe && $0.createdAt > seen }.count
    }

    // MARK: Who is listening

    private final class Weak {
        weak var listener: DeskListener?
        init(_ l: DeskListener) { listener = l }
    }

    func addListener(_ l: DeskListener) {
        listeners[ObjectIdentifier(l)] = Weak(l)
        if stream == nil && started && token != nil { startStream() }
    }

    func removeListener(_ l: DeskListener) {
        listeners[ObjectIdentifier(l)] = nil
        listeners = listeners.filter { $0.value.listener != nil }
        if listeners.isEmpty { stopStream() }
    }

    private var live: [DeskListener] { listeners.values.compactMap { $0.listener } }

    // MARK: Who is chatting

    func login(_ u: VartaDeskUser) {
        let changed = user?.userId != u.userId
        user = u
        guard changed else { return }
        // Someone else now: what is on screen is theirs, fetched again.
        sessionAt = nil
        pushRegistered = false
        stopStream()
        if !live.isEmpty { open(quiet: token != nil) }
    }

    func logout() {
        // This phone stops getting the last person's notifications; the next session registers it afresh.
        if let t = prefs.string(forKey: key("pushToken")), token != nil { post("/push/remove", ["token": t]) { _, _ in } }
        pushRegistered = false
        user = nil
        stopStream()
        token = nil
        prefs.removeObject(forKey: key("token"))
        prefs.removeObject(forKey: key("seenAt"))
        messages = []
        tickets = []
        email = nil
        started = false
        closed = false
        verified = false
        sessionAt = nil
        changed()
    }

    // MARK: Opening

    /**
     * Open (or reopen) the session and load the conversation so far. A screen
     * opening calls this; `quiet` only needs the look and, for someone who has
     * chatted before, their unread replies. A session less than `fresh`
     * seconds old is reused.
     */
    func open(quiet: Bool = false, fresh: TimeInterval = 0) {
        if fresh > 0, let at = sessionAt, Date().timeIntervalSince(at) < fresh { return }
        if quiet && token == nil { return loadConfig() }
        if !quiet {
            loading = true
            changed()
        }
        var body = details()
        body["token"] = token ?? NSNull()
        post("/session", body) { [weak self] r, err in
            guard let self else { return }
            self.loading = false
            guard let r else { return quiet ? self.changed() : self.fail(err) }
            self.sessionAt = Date()
            self.token = (r["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            self.prefs.set(self.token, forKey: self.key("token"))
            self.look = Self.lookOf(r)
            self.started = r["started"] as? Bool ?? false
            self.closed = r["closed"] as? Bool ?? false
            self.verified = r["verified"] as? Bool ?? false
            self.email = (r["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            self.messages = Self.parseMessages(r["messages"])
            self.tickets = Self.parseTickets(r["tickets"])
            self.changed()
            if self.started && !self.live.isEmpty { self.startStream() }
            self.registerPush()
        }
    }

    /** How the chat looks, without starting a session (nothing stored on the phone). */
    private func loadConfig() {
        if look != nil { return changed() }
        get("/config") { [weak self] r, _ in
            guard let self else { return }
            if let r { self.look = Self.lookOf(r) }
            self.changed()
        }
    }

    /** Who is chatting and from where, as the website widget sends it. */
    private func details() -> [String: Any] {
        var o: [String: Any] = [
            "page": "ios-app:\(Bundle.main.bundleIdentifier ?? "app")",
            "title": Self.appName(),
        ]
        if let u = user {
            o["userId"] = u.userId
            o["userHash"] = u.userHash
            if let n = u.name { o["name"] = n }
            if let e = u.email { o["email"] = e }
        }
        return o
    }

    // MARK: Writing

    func send(_ text: String) {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !body.isEmpty else { return }
        tempIds += 1
        let temp = DeskMessage(id: "local-\(tempIds)", fromMe: true, type: "text", body: body, mediaFilename: nil, createdAt: Self.nowIso(), pending: true)
        messages.append(temp)
        changed()
        // Who they are goes with the message too: the first one creates the chat the team sees.
        var payload = details()
        payload["body"] = body
        post("/messages", payload) { [weak self] r, err in
            guard let self else { return }
            if let m = (r?["message"] as? [String: Any]).map(Self.parseMessage) {
                self.messages = Self.merge(self.messages.filter { $0.id != temp.id }, [m])
                // The first message starts the conversation: now there is one to listen to.
                if !self.started {
                    self.started = true
                    self.startStream()
                }
            } else {
                self.messages = self.messages.map { $0.id == temp.id ? { var x = $0; x.pending = false; x.failed = err ?? "Not sent."; return x }($0) : $0 }
            }
            self.changed()
        }
    }

    /**
     * Send a picture or a file (DK25c), already made ready by DeskFiles: the
     * bytes go up raw, the name in x-filename, as the website widget sends them.
     */
    func sendFile(_ file: DeskFiles.Ready) {
        tempIds += 1
        let temp = DeskMessage(id: "local-\(tempIds)", fromMe: true, type: file.mime.hasPrefix("image/") ? "image" : "document",
                               body: nil, mediaFilename: file.name, createdAt: Self.nowIso(), mediaMime: file.mime, pending: true)
        messages.append(temp)
        changed()
        var r = request("/files")
        r.httpMethod = "POST"
        r.setValue(file.mime, forHTTPHeaderField: "Content-Type")
        r.setValue(Self.enc(file.name), forHTTPHeaderField: "x-filename")
        r.httpBody = file.data
        r.timeoutInterval = 120
        run(r) { [weak self] res, err in
            guard let self else { return }
            if let m = (res?["message"] as? [String: Any]).map(Self.parseMessage) {
                self.messages = Self.merge(self.messages.filter { $0.id != temp.id }, [m])
                if !self.started {
                    self.started = true
                    self.startStream()
                }
            } else {
                self.messages = self.messages.map { $0.id == temp.id ? { var x = $0; x.pending = false; x.failed = err ?? "Not sent."; return x }($0) : $0 }
            }
            self.changed()
        }
    }

    /** A picture, fetched once and kept while the app runs (keyed without the link's expiry). */
    func image(_ url: String, _ done: @escaping (UIImage?) -> Void) {
        let key = String(url.split(separator: "?", maxSplits: 1).first ?? "")
        if let hit = images.object(forKey: key as NSString) { return done(hit) }
        guard let u = URL(string: url) else { return done(nil) }
        http.dataTask(with: u) { [weak self] data, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200
            let img = ok ? data.flatMap(UIImage.init(data:)).map { DeskFiles.small($0, edge: 1080) } : nil
            DispatchQueue.main.async {
                if let img { self?.images.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * 4)) }
                done(img)
            }
        }.resume()
    }

    private let images: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    /** The person can see the chat: the team sees "Seen", and nothing is unread. */
    func markSeen() {
        guard let last = messages.last(where: { !$0.fromMe && !$0.pending }) else { return }
        let had = unread
        prefs.set(last.createdAt, forKey: key("seenAt"))
        if had > 0 { changed() }
        if started { post("/seen", [:]) { _, _ in } }
    }

    private var lastTypingAt = Date.distantPast
    func typing() {
        let now = Date()
        guard started, now.timeIntervalSince(lastTypingAt) >= 3 else { return }
        lastTypingAt = now
        post("/typing", [:]) { _, _ in }
    }

    // MARK: Phone notifications (DK25d)

    private var pushRegistered = false

    /** The phone's Apple device token, in hex. Sent once there is a chat session. */
    func setPushToken(_ t: String?) {
        let old = prefs.string(forKey: key("pushToken"))
        if t == old { return registerPush() }
        if let old, token != nil { post("/push/remove", ["token": old]) { _, _ in } }
        if let t { prefs.set(t, forKey: key("pushToken")) } else { prefs.removeObject(forKey: key("pushToken")) }
        pushRegistered = false
        guard t != nil else { return }
        // A session already open: register now. Otherwise the next one does (a quiet one, so nothing is drawn).
        if token != nil && sessionAt != nil { registerPush() } else { open(quiet: true) }
    }

    private func registerPush() {
        guard let t = prefs.string(forKey: key("pushToken")), !pushRegistered, token != nil else { return }
        pushRegistered = true
        post("/push", ["token": t, "platform": "ios"]) { [weak self] _, err in
            if err != nil { self?.pushRegistered = false }
        }
    }

    /** A notification came while the app is open: fetch what it was about, so counts are right. */
    func pushArrived() {
        if token != nil { open(quiet: true) }
    }

    // MARK: Tickets (DK7)

    /** Raise a ticket. `mail` only when the chat doesn't know their email yet. */
    func raiseTicket(subject: String, details: String, mail: String?, done: @escaping (String?) -> Void) {
        var body = self.details()
        body["subject"] = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        body["details"] = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = mail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !m.isEmpty { body["email"] = m }
        post("/tickets", body) { [weak self] r, err in
            guard let self else { return }
            guard let r else { return done(err ?? "Not sent.") }
            if let t = r["ticket"] as? [String: Any] { self.tickets = Self.mergeTickets(self.tickets, [Self.parseTicket(t)]) }
            if let msg = r["message"] as? [String: Any] { self.messages = Self.merge(self.messages, [Self.parseMessage(msg)]) }
            if !m.isEmpty { self.email = m }
            if !self.started {
                self.started = true
                self.startStream()
            }
            self.changed()
            done(nil)
        }
    }

    // MARK: Help (DK8)

    /** The help centre's articles, in its own order. Searching needs no chat and stores nothing. */
    func loadHelp(_ done: @escaping ([DeskArticleItem]) -> Void) {
        get("/help") { r, _ in
            let folders = r?["folders"] as? [[String: Any]] ?? []
            done(folders.flatMap { Self.parseArticles($0["articles"]) })
        }
    }

    /** `final`: they stopped typing, so finding nothing is reported to the business. */
    func searchHelp(_ q: String, final: Bool, _ done: @escaping ([DeskArticleItem]) -> Void) {
        get("/help?q=" + Self.enc(q) + (final ? "&final=1" : "")) { r, _ in
            done(Self.parseArticles(r?["articles"]))
        }
    }

    /** One article: its title, folder and body as HTML. */
    func article(_ slug: String, _ done: @escaping ([String: Any]?, String?) -> Void) {
        get("/help/" + Self.enc(slug)) { r, err in done(r?["article"] as? [String: Any], err) }
    }

    func react(_ slug: String, _ reaction: String, previous: String?) {
        var b: [String: Any] = ["reaction": reaction]
        if let previous { b["previous"] = previous }
        post("/help/" + Self.enc(slug) + "/react", b) { _, _ in }
    }

    // MARK: Live replies (server-sent events)

    private func startStream() {
        guard stream == nil, let token, !live.isEmpty else { return }
        var req = request("/stream?token=" + Self.enc(token))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let s = DeskStream()
        stream = s
        s.onEvent = { [weak self] event, data in self?.handleEvent(event, data) }
        s.onOpen = { [weak self] in self?.retry = 1 }
        s.onEnd = { [weak self, weak s] in
            guard let self, let s else { return }
            if self.stream === s { self.stream = nil }
            guard !self.live.isEmpty, !s.cancelled else { return }
            let wait = self.retry
            self.retry = min(self.retry * 2, 30)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.startStream() }
            // Anything sent while the stream was down.
            self.catchUp()
        }
        s.start(req)
    }

    private func stopStream() {
        stream?.cancel()
        stream = nil
    }

    private func handleEvent(_ event: String, _ raw: String) {
        guard let data = raw.data(using: .utf8),
              let e = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        switch event {
        case "message":
            guard let m = e["message"] as? [String: Any] else { return }
            // Some events carry only the id (a message that arrived another way): fetch it.
            if m["from"] == nil { return catchUp() }
            let msg = Self.parseMessage(m)
            if !msg.fromMe { teamTyping = nil }
            messages = Self.merge(messages, [msg])
            if chatVisible && !msg.fromMe { markSeen() }
            changed()
        case "typing":
            guard e["from"] as? String == "team" else { return }
            let name = (e["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"
            teamTyping = name
            changed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.teamTyping == name else { return }
                self.teamTyping = nil
                self.changed()
            }
        case "ticket":
            guard let t = e["ticket"] as? [String: Any] else { return }
            tickets = Self.mergeTickets(tickets, [Self.parseTicket(t)])
            changed()
        case "rating":
            if e["rating"] is NSNull || e["rating"] == nil {
                closed = false
                changed()
            }
        default:
            break
        }
    }

    private func catchUp() {
        let after = messages.last(where: { !$0.pending && $0.failed == nil })?.createdAt
        get("/messages" + (after.map { "?after=" + Self.enc($0) } ?? "")) { [weak self] r, _ in
            guard let self else { return }
            let fresh = Self.parseMessages(r?["messages"])
            guard !fresh.isEmpty else { return }
            self.messages = Self.merge(self.messages, fresh)
            if self.chatVisible { self.markSeen() }
            self.changed()
        }
    }

    // MARK: Plumbing

    private func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "\(apiBase)/desk/v1/\(workspace)\(path)")!)
        r.setValue("vartadesk-ios/\(VartaDesk.version)", forHTTPHeaderField: "X-Varta-Client")
        let d = UIDevice.current
        r.setValue("VartaDesk-iOS/\(VartaDesk.version) (\(d.systemName) \(d.systemVersion); \(Self.model()))", forHTTPHeaderField: "User-Agent")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func post(_ path: String, _ body: [String: Any], _ done: @escaping ([String: Any]?, String?) -> Void) {
        var r = request(path)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        run(r, done)
    }

    private func get(_ path: String, _ done: @escaping ([String: Any]?, String?) -> Void) {
        run(request(path), done)
    }

    private func run(_ req: URLRequest, _ done: @escaping ([String: Any]?, String?) -> Void) {
        http.dataTask(with: req) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil || code == 0 {
                    return done(nil, "No connection. Check the internet and try again.")
                }
                if (200..<300).contains(code) { return done(json ?? [:], nil) }
                // The chat's token ran out or belonged to someone else: start over next time.
                if code == 401 {
                    self.token = nil
                    self.prefs.removeObject(forKey: self.key("token"))
                }
                done(nil, (json?["error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Something went wrong.")
            }
        }.resume()
    }

    private func fail(_ err: String?) {
        changed()
        let msg = err ?? "Something went wrong."
        live.forEach { $0.deskError(msg) }
    }

    private func changed() {
        live.forEach { $0.deskChanged() }
    }

    func close() {
        stopStream()
        listeners.removeAll()
    }

    // MARK: Reading the server's answers

    static func appName() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "iOS app"
    }

    /** "iPhone17,1" rather than just "iPhone", so the team can tell phones apart. */
    static func model() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim + " Simulator" }
        var sys = utsname()
        uname(&sys)
        let id = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return id.isEmpty ? UIDevice.current.model : id
    }

    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func nowIso() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private static func str(_ o: [String: Any], _ k: String) -> String? {
        (o[k] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func parseMessage(_ o: [String: Any]) -> DeskMessage {
        DeskMessage(
            id: o["id"] as? String ?? "",
            fromMe: o["from"] as? String == "me",
            type: o["type"] as? String ?? "text",
            body: str(o, "body"),
            mediaFilename: str(o, "mediaFilename"),
            createdAt: o["createdAt"] as? String ?? "",
            mediaUrl: str(o, "mediaUrl"),
            mediaMime: str(o, "mediaMime")
        )
    }

    static func parseMessages(_ a: Any?) -> [DeskMessage] {
        ((a as? [[String: Any]]) ?? []).map(parseMessage)
    }

    static func parseTicket(_ o: [String: Any]) -> DeskTicket {
        DeskTicket(
            ref: (o["ref"] as? String) ?? (o["ref"] as? Int).map(String.init) ?? "",
            subject: o["subject"] as? String ?? "",
            details: str(o, "details"),
            status: o["status"] as? String ?? "open",
            label: str(o, "label"),
            updatedAt: o["updatedAt"] as? String ?? ""
        )
    }

    static func parseTickets(_ a: Any?) -> [DeskTicket] {
        ((a as? [[String: Any]]) ?? []).map(parseTicket)
    }

    static func parseArticles(_ a: Any?) -> [DeskArticleItem] {
        ((a as? [[String: Any]]) ?? []).map {
            DeskArticleItem(slug: $0["slug"] as? String ?? "", title: $0["title"] as? String ?? "", summary: $0["summary"] as? String ?? "")
        }
    }

    /** Add or replace by reference, newest change first. */
    static func mergeTickets(_ old: [DeskTicket], _ add: [DeskTicket]) -> [DeskTicket] {
        var byRef: [String: DeskTicket] = [:]
        for t in old + add { byRef[t.ref] = t }
        return byRef.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /** Add or replace by id, oldest first, messages still sending last. */
    static func merge(_ old: [DeskMessage], _ add: [DeskMessage]) -> [DeskMessage] {
        var byId: [String: DeskMessage] = [:]
        var order: [String] = []
        for m in old + add {
            if byId[m.id] == nil { order.append(m.id) }
            byId[m.id] = m
        }
        return order.compactMap { byId[$0] }.enumerated().sorted { a, b in
            if a.element.pending != b.element.pending { return !a.element.pending }
            if a.element.createdAt != b.element.createdAt { return a.element.createdAt < b.element.createdAt }
            return a.offset < b.offset
        }.map { $0.element }
    }

    static func lookOf(_ r: [String: Any]) -> DeskLook {
        let a = r["appearance"] as? [String: Any] ?? [:]
        let st = r["status"] as? [String: Any] ?? [:]
        return DeskLook(
            name: r["name"] as? String ?? "",
            color: UIColor(hex: a["color"] as? String) ?? UIColor(red: 0, green: 0x4C / 255, blue: 0x3D / 255, alpha: 1),
            greeting: a["greeting"] as? String ?? "Hi there",
            intro: a["intro"] as? String ?? "",
            reply: st["reply"] as? String ?? "in a few minutes",
            open: st["open"] as? Bool ?? true,
            backAt: str(st, "backAt"),
            ticketForm: r["ticketForm"] as? Bool ?? false,
            helpArticles: (r["help"] as? [String: Any])?["articles"] as? Int ?? 0,
            branding: r["branding"] as? Bool ?? false
        )
    }
}

/**
 * The live stream, read by hand: lines of "event:" and "data:", an empty
 * line ends an event, ":" lines are the server's pings (every 25 seconds, so
 * a minute of silence means the connection dropped). Callbacks on the main thread.
 */
final class DeskStream: NSObject, URLSessionDataDelegate {
    var onOpen: (@MainActor () -> Void)?
    var onEvent: (@MainActor (String, String) -> Void)?
    var onEnd: (@MainActor () -> Void)?
    private(set) var cancelled = false
    private var session: URLSession?
    private var buffer = Data()
    private var event = "message"
    private var data = ""

    func start(_ req: URLRequest) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 7 * 24 * 3600
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: q)
        session = s
        s.dataTask(with: req).resume()
    }

    func cancel() {
        cancelled = true
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return completionHandler(.cancel) }
        completionHandler(.allow)
        main { $0.onOpen?() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            let line = String(decoding: lineData, as: UTF8.self)
            if line.isEmpty {
                if !data.isEmpty {
                    let (e, d) = (event, data)
                    main { $0.onEvent?(e, d) }
                }
                event = "message"
                data = ""
            } else if line.hasPrefix(":") {
                continue
            } else if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        main { $0.onEnd?() }
    }

    private func main(_ f: @escaping @MainActor (DeskStream) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { f(self) }
        }
    }
}

extension UIColor {
    /** "#RRGGBB" from the business's settings. */
    convenience init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
