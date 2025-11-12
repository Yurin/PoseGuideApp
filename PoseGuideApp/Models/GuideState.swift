// Models/GuideState.swift
import Foundation

public struct GuideState: Codable, Equatable {
    public var opacity: Double = 0.7
    public var scale: Double = 1.0
    public var offsetX: Double = 0
    public var offsetY: Double = 0
}

public enum GuideEventType: String, Codable {
    case update
    case lock
}

public struct GuideMessage: Codable, Equatable {
    public var type: GuideEventType
    public var state: GuideState
    public var roomName: String
}

