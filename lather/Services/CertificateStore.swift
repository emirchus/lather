import Foundation
import Observation

/// Manages client certificates (.pem, .crt, .key) used for mTLS-authenticated
/// SOAP services (e.g. AFIP WSAA tickets, OpenSSL-signed PEM certs).
protocol CertificateStoring {
    func allCertificates() -> [ClientCertificate]
    func addCertificate(_ certificate: ClientCertificate) throws
    func removeCertificate(id: ClientCertificate.ID) throws
}

/// In-memory stub. Future implementation should persist certificate/key
/// references securely in the Keychain rather than keeping raw file URLs.
@Observable
final class KeychainCertificateStore: CertificateStoring {
    private var certificates: [ClientCertificate] = []

    func allCertificates() -> [ClientCertificate] {
        certificates
    }

    func addCertificate(_ certificate: ClientCertificate) throws {
        // TODO: persist the certificate/key reference in the Keychain.
        certificates.append(certificate)
    }

    func removeCertificate(id: ClientCertificate.ID) throws {
        // TODO: remove the corresponding Keychain item.
        certificates.removeAll { $0.id == id }
    }
}
