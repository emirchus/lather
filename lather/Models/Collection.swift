import Foundation

struct Collection: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var requests: [SOAPRequest]

    init(id: UUID = UUID(), name: String, requests: [SOAPRequest]) {
        self.id = id
        self.name = name
        self.requests = requests
    }
}

extension Collection {
    static let sampleData: [Collection] = [
        Collection(
            name: "AFIP WSAA",
            requests: [
                SOAPRequest(
                    name: "LoginCms",
                    endpointURL: "https://wsaahomo.afip.gov.ar/ws/services/LoginCms",
                    soapAction: "",
                    xmlBody: """
                    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
                      <soapenv:Header/>
                      <soapenv:Body>
                        <loginCms>
                          <in0><CMS-base64></in0>
                        </loginCms>
                      </soapenv:Body>
                    </soapenv:Envelope>
                    """
                )
            ]
        ),
        Collection(
            name: "Weather Demo",
            requests: [
                SOAPRequest(
                    name: "GetCityWeatherByZIP",
                    endpointURL: "https://www.webservicex.net/globalweather.asmx",
                    soapAction: "http://www.webserviceX.NET/GetCityWeatherByZIP",
                    xmlBody: """
                    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
                      <soapenv:Header/>
                      <soapenv:Body>
                        <GetCityWeatherByZIP>
                          <ZIP>10001</ZIP>
                        </GetCityWeatherByZIP>
                      </soapenv:Body>
                    </soapenv:Envelope>
                    """
                )
            ]
        )
    ]
}
