import Foundation

enum ProcessRunner {
    struct ProcessError: LocalizedError {
        var command: String
        var arguments: [String]
        var exitCode: Int32
        var output: String

        var errorDescription: String? {
            "\(command) exited with \(exitCode): \(output)"
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let combined = output + (errorOutput.isEmpty ? "" : "\n\(errorOutput)")

            guard process.terminationStatus == 0 else {
                throw ProcessError(
                    command: executableURL.path,
                    arguments: arguments,
                    exitCode: process.terminationStatus,
                    output: combined
                )
            }

            return output
        }.value
    }
}
