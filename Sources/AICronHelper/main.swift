import Foundation

// `AICronHelper --dump`：把采集结果以 JSON 打到标准输出，用于核对数据
if CommandLine.arguments.contains("--dump") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        let data = try encoder.encode(Collector.collectAll())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("导出失败：\(error)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    AICronHelperApp.main()
}
