import Foundation
@main struct ConnectionDiagnostic {
 static func main() async {
  for provider in ["fireworks", "vertex"] {
   do {
    let http = try SessionHTTP.load(provider: provider)
    let reading: Reading
    if provider == "fireworks" { reading = try await FireworksProvider(http:http,account:Balance.initial[1].account).fetchBalance() }
    else { reading = try await GoogleProvider(http:http,account:Balance.initial[0].account).fetchBalance() }
    print("\(provider): verified USD \(reading.remaining)")
   } catch { print("\(provider): \(error.localizedDescription)") }
  }
 }
}
