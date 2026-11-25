# AmneziaWG Apple

Source: https://github.com/amnezia-vpn/amneziawg-apple/tree/v3.1.5  
Revision: `3bca528aca844bbe6b665d8ab5c6724cd261fd54`

- `WireGuardKit`, `WireGuardKitC`, and the AmneziaWG Go bridge are taken from the release above.
- The upstream wg-quick configuration parser and its string helper are part of the local `WireGuardKit` target. The parser's initializer is public for use by the app and extension.
- The local Swift package links the architecture-specific Go archive that the Xcode build produces. The build compiles only `api-apple.go` for AmneziaWG and applies the upstream Go boot-time patch. The Xray bridge and its separate HTTP/2 patch are omitted.
- The original license and licenses for the linked Go components accompany the source and the app bundle.
