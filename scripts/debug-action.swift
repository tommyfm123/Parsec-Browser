import Foundation
let arguments = CommandLine.arguments.dropFirst()
let action = arguments.first ?? "snapshot"
let argument = arguments.dropFirst().first ?? action
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("dev.tommy.parsec.debug"), object: nil,
    userInfo: ["action": action, "argument": argument], deliverImmediately: true
)
