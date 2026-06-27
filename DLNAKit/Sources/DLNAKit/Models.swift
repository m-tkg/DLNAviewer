import Foundation

/// DLNA/UPnP のメディアサーバー（ContentDirectory を持つデバイス）。
public struct MediaServer: Identifiable, Hashable, Sendable, Codable {
    /// デバイスの UDN（Unique Device Name）。無ければ記述 URL を ID 代わりに使う。
    public var id: String
    public var friendlyName: String
    /// デバイス記述 XML（device description）の URL。
    public var descriptionURL: URL
    /// ContentDirectory サービスの controlURL（絶対 URL に解決済み）。
    public var contentDirectoryControlURL: URL?
    /// 手動登録か自動探索か。
    public var origin: Origin

    public enum Origin: String, Hashable, Sendable, Codable {
        case manual
        case discovered
    }

    public init(
        id: String,
        friendlyName: String,
        descriptionURL: URL,
        contentDirectoryControlURL: URL? = nil,
        origin: Origin
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.descriptionURL = descriptionURL
        self.contentDirectoryControlURL = contentDirectoryControlURL
        self.origin = origin
    }
}

/// ContentDirectory のブラウズ結果に含まれる 1 オブジェクト（コンテナまたはアイテム）。
public enum DIDLObject: Identifiable, Hashable, Sendable {
    case container(MediaContainer)
    case item(MediaItem)

    public var id: String {
        switch self {
        case .container(let c): return c.id
        case .item(let i): return i.id
        }
    }

    public var title: String {
        switch self {
        case .container(let c): return c.title
        case .item(let i): return i.title
        }
    }
}

/// フォルダ（DIDL-Lite の `<container>`）。
public struct MediaContainer: Identifiable, Hashable, Sendable {
    public var id: String
    public var parentID: String
    public var title: String
    /// 子要素数（`childCount` 属性、不明なら nil）。
    public var childCount: Int?

    public init(id: String, parentID: String, title: String, childCount: Int? = nil) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.childCount = childCount
    }
}

/// 再生可能なメディア（DIDL-Lite の `<item>`）。動画 DMP では動画アイテムが対象。
public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var parentID: String
    public var title: String
    /// upnp:class（例: `object.item.videoItem`）。
    public var upnpClass: String
    /// 再生用リソースの候補（画像以外の `<res>`）。先頭が第一候補。
    public var resources: [MediaResource]
    /// サムネイル画像のリソース（`image/*` の `<res>`）。
    public var thumbnails: [MediaResource]
    /// `upnp:albumArtURI`（あれば最優先のサムネイル）。
    public var albumArtURI: URL?

    public init(
        id: String,
        parentID: String,
        title: String,
        upnpClass: String,
        resources: [MediaResource],
        thumbnails: [MediaResource] = [],
        albumArtURI: URL? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.upnpClass = upnpClass
        self.resources = resources
        self.thumbnails = thumbnails
        self.albumArtURI = albumArtURI
    }

    /// 第一候補の再生 URL。
    public var primaryURL: URL? { resources.first?.url }

    /// サーバー提供のサムネイル URL（albumArtURI を優先、無ければ画像 res）。
    public var thumbnailURL: URL? { albumArtURI ?? thumbnails.first?.url }

    /// upnp:class が動画かどうか。
    public var isVideo: Bool { upnpClass.contains("videoItem") }
}

/// `<res>` 要素 = 再生可能なリソース 1 本。
public struct MediaResource: Hashable, Sendable, Codable {
    public var url: URL
    /// protocolInfo（例: `http-get:*:video/mp4:*`）。
    public var protocolInfo: String?
    /// 再生時間（秒）。`res@duration` を解釈。不明なら nil。
    public var durationSeconds: Double?
    /// ファイルサイズ（バイト、`res@size`）。
    public var size: Int64?
    /// 解像度（`res@resolution`、例: `1920x1080`）。
    public var resolution: String?

    public init(
        url: URL,
        protocolInfo: String? = nil,
        durationSeconds: Double? = nil,
        size: Int64? = nil,
        resolution: String? = nil
    ) {
        self.url = url
        self.protocolInfo = protocolInfo
        self.durationSeconds = durationSeconds
        self.size = size
        self.resolution = resolution
    }

    /// MIME タイプ（protocolInfo の 3 番目フィールド）。
    public var mimeType: String? {
        guard let parts = protocolInfo?.split(separator: ":", omittingEmptySubsequences: false),
              parts.count >= 3 else { return nil }
        let mime = String(parts[2])
        return mime.isEmpty ? nil : mime
    }
}
