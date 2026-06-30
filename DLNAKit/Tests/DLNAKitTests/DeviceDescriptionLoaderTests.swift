import Foundation
import Testing
@testable import DLNAKit

@Suite("DeviceDescriptionLoader")
struct DeviceDescriptionLoaderTests {
    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("friendlyName / UDN / ContentDirectory controlURL を解析する")
    func parsesDevice() throws {
        let data = try Self.fixture("device_description")
        let descURL = URL(string: "http://192.168.1.10:8200/rootDesc.xml")!
        let server = try DeviceDescriptionLoader.parse(data, descriptionURL: descURL, origin: .manual)

        #expect(server.friendlyName == "My NAS DLNA")
        #expect(server.id == "uuid:4d696e69-444c-164e-9d41-001122334455")
        // 相対 controlURL は記述 URL を基準に絶対化される
        #expect(server.contentDirectoryControlURL
            == URL(string: "http://192.168.1.10:8200/ctl/ContentDir"))
        #expect(server.origin == .manual)
    }

    @Test("ContentDirectory が無ければエラー")
    func throwsWhenNoContentDirectory() throws {
        let xml = """
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>No CD</friendlyName>
            <UDN>uuid:abc</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <controlURL>/ctl/cm</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
        #expect(throws: DeviceDescriptionLoader.LoaderError.noContentDirectory) {
            _ = try DeviceDescriptionLoader.parse(Data(xml.utf8),
                                                  descriptionURL: URL(string: "http://h/d.xml")!)
        }
    }

    @Test("壊れた応答は malformedXML に受信本文の先頭を含めて投げる")
    func malformedIncludesSnippet() {
        let body = "<html><body>503 truncated"   // XML として不正
        #expect {
            _ = try DeviceDescriptionLoader.parse(Data(body.utf8),
                                                  descriptionURL: URL(string: "http://h/d.xml")!)
        } throws: { error in
            guard case let DeviceDescriptionLoader.LoaderError.malformedXML(snippet) = error else { return false }
            return snippet.contains("503 truncated")
        }
    }

    @Test("空の応答でも malformedXML（空である旨を示す）")
    func emptyResponse() {
        #expect {
            _ = try DeviceDescriptionLoader.parse(Data(), descriptionURL: URL(string: "http://h/d.xml")!)
        } throws: { error in
            if case .malformedXML = error as! DeviceDescriptionLoader.LoaderError { return true }
            return false
        }
    }

    @Test("load() は transport から取得して解析する")
    func loadUsesTransport() async throws {
        let data = try Self.fixture("device_description")
        let descURL = URL(string: "http://192.168.1.10:8200/rootDesc.xml")!
        let loader = DeviceDescriptionLoader { url in
            #expect(url == descURL)
            return data
        }
        let server = try await loader.load(descriptionURL: descURL, origin: .discovered)
        #expect(server.friendlyName == "My NAS DLNA")
        #expect(server.origin == .discovered)
    }
}
