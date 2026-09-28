func expectDestination(_ input: String, _ expected: String?) {
    let actual = InputResolver.destination(for: input)?.absoluteString
    assert(actual == expected, "\(input) → \(actual ?? "nil"), expected \(expected ?? "nil")")
}

expectDestination("github.com", "https://github.com")
expectDestination("localhost:3000", "http://localhost:3000")
expectDestination("app.test/login", "http://app.test/login")
expectDestination("https://polar.sh/pricing", "https://polar.sh/pricing")
expectDestination("swift concurrency", "https://www.google.com/search?q=swift%20concurrency")
expectDestination("hello", "https://www.google.com/search?q=hello")
expectDestination("v1.2", "https://www.google.com/search?q=v1.2")
expectDestination("   ", nil)
expectDestination("about:blank", "about:blank")
print("checks passed")
