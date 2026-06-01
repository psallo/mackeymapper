import Foundation
import Security
import CryptoKit
import Network

/// Manages the self-signed TLS certificate used by the Bonjour server.
/// Certificate + key are generated once via openssl and stored in Application Support.
final class CertificateManager {
    static let shared = CertificateManager()
    private init() {}

    private let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacLauncherRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var cachedIdentity: SecIdentity?
    private var cachedFingerprint: String?

    // MARK: - Public API

    func identity() throws -> SecIdentity {
        if let cached = cachedIdentity { return cached }
        let identity = try loadOrCreateIdentity()
        cachedIdentity = identity
        return identity
    }

    /// SHA-256 fingerprint of the DER-encoded certificate (hex string)
    func certFingerprint() throws -> String {
        if let fp = cachedFingerprint { return fp }
        let identity = try self.identity()
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let certificate = cert else { throw CertError.noCertificate }
        let derData = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: derData)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        cachedFingerprint = fingerprint
        return fingerprint
    }

    /// Returns NWProtocolTLS.Options configured with our identity
    func tlsServerOptions() throws -> NWProtocolTLS.Options {
        let identity = try self.identity()
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let cert = certificate else { throw CertError.noCertificate }

        let options = NWProtocolTLS.Options()
        let secIdentityRef = identity as CFTypeRef
        let certRef = cert as CFTypeRef
        let certArray = [certRef] as CFArray

        sec_protocol_options_set_local_identity(
            options.securityProtocolOptions,
            sec_identity_create(identity)!
        )
        sec_protocol_options_append_tls_ciphersuite(
            options.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_AES_256_GCM_SHA384))!
        )
        sec_protocol_options_set_min_tls_protocol_version(
            options.securityProtocolOptions,
            .TLSv12
        )
        _ = secIdentityRef  // suppress unused warning
        _ = certArray

        return options
    }

    // MARK: - Private

    private var p12URL: URL { appSupportURL.appendingPathComponent("server.p12") }
    private var fingerprintURL: URL { appSupportURL.appendingPathComponent("cert.fingerprint") }
    private static let p12Password = "mlr-internal-p12-pw"

    private func loadOrCreateIdentity() throws -> SecIdentity {
        if FileManager.default.fileExists(atPath: p12URL.path) {
            if let identity = try? importP12() { return identity }
        }
        try generateCertificate()
        return try importP12()
    }

    private func generateCertificate() throws {
        let certURL = appSupportURL.appendingPathComponent("server.crt")
        let keyURL  = appSupportURL.appendingPathComponent("server.key")

        // Generate self-signed cert via LibreSSL (ships with macOS)
        let genResult = try runProcess("/usr/bin/openssl", args: [
            "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", keyURL.path,
            "-out",    certURL.path,
            "-days",   "3650",
            "-nodes",
            "-subj",   "/CN=MacLauncherRemote/O=MacLauncher/C=US"
        ])
        guard genResult == 0 else { throw CertError.opensslFailed("generate cert") }

        // Pack into PKCS12 for easy identity import
        let exportResult = try runProcess("/usr/bin/openssl", args: [
            "pkcs12", "-export",
            "-out",    p12URL.path,
            "-inkey",  keyURL.path,
            "-in",     certURL.path,
            "-passout", "pass:\(Self.p12Password)",
            "-legacy"   // compatibility flag in LibreSSL
        ])
        // LibreSSL may not support -legacy; retry without it
        if exportResult != 0 {
            let retry = try runProcess("/usr/bin/openssl", args: [
                "pkcs12", "-export",
                "-out",    p12URL.path,
                "-inkey",  keyURL.path,
                "-in",     certURL.path,
                "-passout", "pass:\(Self.p12Password)"
            ])
            guard retry == 0 else { throw CertError.opensslFailed("export p12") }
        }

        // Clean up PEM files (p12 is all we need)
        try? FileManager.default.removeItem(at: certURL)
        try? FileManager.default.removeItem(at: keyURL)

        // Invalidate cache
        cachedIdentity = nil
        cachedFingerprint = nil
    }

    private func importP12() throws -> SecIdentity {
        let p12Data = try Data(contentsOf: p12URL)
        let options: [String: Any] = [kSecImportExportPassphrase as String: Self.p12Password]
        var rawItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let first = items.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw CertError.importFailed(status)
        }
        // swiftlint:disable:next force_cast
        return (identity as! SecIdentity)
    }

    @discardableResult
    private func runProcess(_ executable: String, args: [String]) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }

    // MARK: - Errors
    enum CertError: LocalizedError {
        case opensslFailed(String)
        case importFailed(OSStatus)
        case noCertificate

        var errorDescription: String? {
            switch self {
            case .opensslFailed(let step): return "openssl failed at step: \(step)"
            case .importFailed(let s):     return "PKCS12 import failed: \(s)"
            case .noCertificate:           return "Could not copy certificate from identity"
            }
        }
    }
}
