import Foundation
import DLNAKit

let discovery = SSDPDiscovery()
print("探索中… (4秒)")
let responses = await discovery.search()
print("=== \(responses.count) 件 ===")
for r in responses {
    print("ST=\(r.searchTarget)")
    print("  LOCATION=\(r.location)")
    print("  USN=\(r.usn)")
}
