enum BuildVariant {
    #if OFFLINE
    static let isOffline = true
    static let displayName = "Garabatapp Offline"
    #else
    static let isOffline = false
    static let displayName = "Garabatapp"
    #endif
}
