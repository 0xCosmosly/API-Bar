import Foundation
import CryptoKit
import CoreFoundation

struct CrowbotProvider: BalanceProvider {
    let providerID = "crowbot"
    static let endpoint = "https://chat.crowbot.sh/api/me"
    let http: SessionHTTP
    let expectedAccount: String

    static func credential(in cookies: [StoredCookie]) throws -> String {
        let matches = cookies.filter {
            $0.name == "crowbot_key" && ["chat.crowbot.sh", ".chat.crowbot.sh"].contains($0.domain)
                && $0.expires.map { $0 > Date() } != false
        }
        let values = Set(matches.map(\.value))
        guard values.count == 1, let value = values.first,
              value.count == 16, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw ConnectorError.message("No valid Crowbot sign-in was found. Sign in at chat.crowbot.sh in Brave, then reconnect.")
        }
        return value
    }
    // Crowbot's account number is also a credential. Only a one-way fingerprint
    // reaches the ordinary balance file, menus, or diagnostics.
    static func accountID(credential: String) -> String {
        "crowbot:" + SHA256.hash(data: Data(("APIBar Crowbot account:" + credential).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func validAccount(_ value: String) -> Bool {
        value.hasPrefix("crowbot:") && value.count == 72 && value.dropFirst(8).allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
    static func parse(_ data: Data, account: String) throws -> Reading {
        let json = try ProviderJSON.object(data)
        guard json["error"] == nil, validAccount(account),
              let amount = json["balance_microdollars"] as? NSNumber,
              CFGetTypeID(amount) != CFBooleanGetTypeID() else {
            throw ConnectorError.message("Crowbot did not return a valid account balance. The previous balance was retained.")
        }
        let micros = amount.doubleValue
        guard micros.isFinite, micros >= 0, micros.rounded() == micros, micros < 1_000_000_000_000_000 else {
            throw ConnectorError.message("Crowbot returned an invalid balance. The previous balance was retained.")
        }
        let dollars = micros / 1_000_000
        return Reading(provider: "crowbot", remaining: dollars, currency: "USD", account: account, url: endpoint, expires: nil, reference: PaymentReference.inferTier(for: dollars))
    }
    func fetchBalance() async throws -> Reading {
        var cookies = await http.cookies
        var credential = try? Self.credential(in: cookies)
        if credential == nil {
            if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                cookies = await http.cookies
                credential = try? Self.credential(in: cookies)
            }
        }
        guard let validCredential = credential ?? (try? Self.credential(in: cookies)) else {
            throw ConnectorError.message("No valid Crowbot sign-in was found. Sign in at chat.crowbot.sh in Brave, then reconnect.")
        }
        let account = Self.accountID(credential: validCredential)
        guard expectedAccount.isEmpty || expectedAccount == account else {
            throw ConnectorError.message("This Crowbot sign-in belongs to a different account. The previous balance was retained.")
        }
        var (data, response) = try await http.request(url: URL(string: Self.endpoint)!)
        if response.statusCode != 200 {
            if (try? await http.reloadCookiesFromBrave(interactive: false)) != nil {
                (data, response) = try await http.request(url: URL(string: Self.endpoint)!)
            }
        }
        guard response.statusCode == 200 else {
            throw ConnectorError.message("Crowbot sign-in expired or its balance request failed. Sign in in Brave and reconnect.")
        }
        let reading = try Self.parse(data, account: account)
        try await http.persist()
        return reading
    }
}
