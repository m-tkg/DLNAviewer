import Foundation
import Testing
@testable import DLNAKit

@Suite("SSDPDiscovery")
struct SSDPDiscoveryTests {
    @Test("M-SEARCH リクエストに必須ヘッダが含まれCRLF区切りである")
    func buildsSearchRequest() {
        let req = SSDPDiscovery.makeSearchRequest(searchTarget: "ssdp:all", mx: 3)
        #expect(req.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        #expect(req.contains("HOST: 239.255.255.250:1900\r\n"))
        #expect(req.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(req.contains("MX: 3\r\n"))
        #expect(req.contains("ST: ssdp:all\r\n"))
        #expect(req.hasSuffix("\r\n\r\n"))
    }

    @Test("応答から LOCATION / ST / USN を解析する")
    func parsesResponse() throws {
        let text = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        DATE: Sat, 27 Jun 2026 00:00:00 GMT\r
        EXT:\r
        LOCATION: http://192.168.1.10:8200/rootDesc.xml\r
        SERVER: Linux/3.0 UPnP/1.0 MiniDLNA/1.3.0\r
        ST: urn:schemas-upnp-org:device:MediaServer:1\r
        USN: uuid:abcd::urn:schemas-upnp-org:device:MediaServer:1\r
        \r

        """
        let response = try #require(SSDPDiscovery.parseResponse(text))
        #expect(response.location == URL(string: "http://192.168.1.10:8200/rootDesc.xml"))
        #expect(response.searchTarget == "urn:schemas-upnp-org:device:MediaServer:1")
        #expect(response.usn == "uuid:abcd::urn:schemas-upnp-org:device:MediaServer:1")
    }

    @Test("ヘッダ名の大小文字を区別しない")
    func parsesCaseInsensitiveHeaders() throws {
        let text = "HTTP/1.1 200 OK\r\nlocation: http://h:8200/d.xml\r\nst: ssdp:all\r\n\r\n"
        let response = try #require(SSDPDiscovery.parseResponse(text))
        #expect(response.location == URL(string: "http://h:8200/d.xml"))
        #expect(response.searchTarget == "ssdp:all")
    }

    @Test("LOCATION が無ければ nil")
    func returnsNilWithoutLocation() {
        let text = "HTTP/1.1 200 OK\r\nST: ssdp:all\r\n\r\n"
        #expect(SSDPDiscovery.parseResponse(text) == nil)
    }
}
