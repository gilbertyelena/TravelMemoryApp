//
//  AirlineCheckIn.swift
//  TravelMemory
//
//  Maps a flight to the airline's online check-in page so the
//  check-in reminder can deep-link straight there. Resolution is by
//  flight-number designator ("FR1885" → FR) with the airline name as
//  fallback. Airlines move their check-in URLs around, so several
//  entries point at the homepage — still one tap closer than nothing.
//

import Foundation

enum AirlineCheckIn {

    /// Best-known online check-in (or manage-booking) page per IATA
    /// designator.
    private static let urlsByDesignator: [String: String] = [
        // Europe — low cost
        "FR": "https://www.ryanair.com/gb/en/check-in",
        "U2": "https://www.easyjet.com/en/manage",
        "W6": "https://wizzair.com/en-gb/checkin",
        "W9": "https://wizzair.com/en-gb/checkin",
        "VY": "https://www.vueling.com",
        "EW": "https://www.eurowings.com",
        "DY": "https://www.norwegian.com",
        // Europe — flag carriers
        "LH": "https://www.lufthansa.com/gb/en/online-check-in",
        "BA": "https://www.britishairways.com/travel/managebooking/public/en_gb",
        "AF": "https://wwws.airfrance.fr/check-in",
        "KL": "https://www.klm.com/check-in",
        "LX": "https://www.swiss.com",
        "OS": "https://www.austrian.com",
        "SK": "https://www.flysas.com",
        "AY": "https://www.finnair.com",
        "IB": "https://www.iberia.com",
        "TP": "https://www.flytap.com",
        "LO": "https://www.lot.com",
        "EI": "https://www.aerlingus.com",
        "FI": "https://www.icelandair.com",
        "TK": "https://www.turkishairlines.com/en-int/flights/manage-booking/",
        // Middle East / Asia / Pacific
        "EK": "https://www.emirates.com",
        "QR": "https://www.qatarairways.com",
        "EY": "https://www.etihad.com",
        "SQ": "https://www.singaporeair.com",
        "CX": "https://www.cathaypacific.com",
        "NH": "https://www.ana.co.jp/en/us/",
        "JL": "https://www.jal.co.jp/jp/en/",
        "QF": "https://www.qantas.com",
        "NZ": "https://www.airnewzealand.com",
        // Americas
        "UA": "https://www.united.com/en/us/checkin",
        "AA": "https://www.aa.com",
        "DL": "https://www.delta.com",
        "B6": "https://checkin.jetblue.com",
        "WN": "https://www.southwest.com/air/check-in/",
        "AS": "https://www.alaskaair.com",
        "AC": "https://www.aircanada.com",
    ]

    /// Airline display name → designator, for flights entered without
    /// a parsable flight number.
    private static let designatorsByName: [String: String] = [
        "ryanair": "FR", "easyjet": "U2", "wizz air": "W6", "vueling": "VY",
        "eurowings": "EW", "norwegian": "DY", "lufthansa": "LH",
        "british airways": "BA", "air france": "AF", "klm": "KL",
        "swiss": "LX", "austrian": "OS", "sas": "SK", "finnair": "AY",
        "iberia": "IB", "tap": "TP", "lot": "LO", "aer lingus": "EI",
        "icelandair": "FI", "turkish airlines": "TK", "emirates": "EK",
        "qatar airways": "QR", "etihad": "EY", "singapore airlines": "SQ",
        "cathay pacific": "CX", "ana": "NH", "japan airlines": "JL",
        "qantas": "QF", "air new zealand": "NZ", "united": "UA",
        "american airlines": "AA", "delta": "DL", "jetblue": "B6",
        "southwest": "WN", "alaska airlines": "AS", "air canada": "AC",
    ]

    /// Online check-in page for a flight, if the airline is known.
    static func url(flightNumber: String, airline: String) -> URL? {
        if let designator = designator(from: flightNumber),
           let urlString = urlsByDesignator[designator] {
            return URL(string: urlString)
        }
        let name = airline.lowercased().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            for (key, designator) in designatorsByName where name.contains(key) {
                if let urlString = urlsByDesignator[designator] {
                    return URL(string: urlString)
                }
            }
        }
        return nil
    }

    /// "FR1885" / "FR 1885" → "FR"; "W61234" → "W6"
    private static func designator(from flightNumber: String) -> String? {
        let trimmed = flightNumber.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 3 else { return nil }
        let prefix = String(trimmed.prefix(2))
        let isDesignator = prefix.allSatisfy { $0.isLetter || $0.isNumber }
            && prefix.contains(where: \.isLetter)
        return isDesignator ? prefix : nil
    }
}
