#!/usr/bin/env python3
"""Run production RenameIO in isolation; never touches user/SMB files."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'FlowVision/Sources/ViewControllerExtension/FileOperation.swift').read_text()
helper = source[source.index('enum RenameIO {'):source.index('enum BatchMediaRotation')]
tests = r'''
let a = URL(fileURLWithPath: "/a")
let b = URL(fileURLWithPath: "/b")
for enabled in [false, true] {
    var calls = 0
    var waits = 0
    do {
        try RenameIO.move(from: a, to: b, retryBusy: enabled, operation: { _, _ in
            calls += 1
            if calls < 3 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY)) }
        }, wait: { _ in waits += 1 })
        assert(enabled)
    } catch { assert(!enabled) }
    assert(calls == (enabled ? 3 : 1)); assert(waits == (enabled ? 2 : 0))
}
for code in [EACCES, EPERM, ETIMEDOUT, ENOTCONN, EEXIST] {
    var calls = 0
    do {
        try RenameIO.move(from: a, to: b, retryBusy: true, operation: { _, _ in
            calls += 1
            throw NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])
        }, wait: { _ in assertionFailure("must not retry") })
        assertionFailure("must fail")
    } catch { assert(RenameIO.errorChain(error).contains("NSPOSIXErrorDomain:\(code)")) }
    assert(calls == 1)
}
// A->B, B->A, C->D; fail each possible final phase, retaining identities.
for completed in 0...3 {
    let names = ["a", "b", "c"]
    let targets = ["b", "a", "d"]
    let pending = names.enumerated().map { i, name in
        (source: URL(fileURLWithPath: "/" + name), temp: URL(fileURLWithPath: "/t\(i)"),
         target: URL(fileURLWithPath: "/" + targets[i]))
    }
    var disk: [URL: String] = [:]
    for i in 0..<3 { disk[i < completed ? pending[i].target : pending[i].temp] = names[i] }
    let failures = RenameIO.rollback(pending, completed: completed) { from, to in
        guard let value = disk[from], disk[to] == nil else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST))
        }
        disk[to] = value; disk.removeValue(forKey: from)
    }
    assert(failures.isEmpty)
    for i in 0..<3 { assert(disk[pending[i].source] == names[i]) }
    assert(disk.count == 3)
}
// Real local two-phase move and restoration, with an open file.
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
let dir = root.appendingPathComponent("source")
let temp = root.appendingPathComponent("temp")
try fm.createDirectory(at: dir, withIntermediateDirectories: false)
let child = dir.appendingPathComponent("child")
try Data("unchanged".utf8).write(to: child)
let handle = try FileHandle(forReadingFrom: child)
try RenameIO.move(from: dir, to: temp, retryBusy: false)
try RenameIO.move(from: temp, to: dir, retryBusy: false)
try handle.close()
assert(try String(contentsOf: child, encoding: .utf8) == "unchanged")
print("PASS: retry ablation, permission/uncertain-outcome exclusion, 4 rollback stages, local open-file roundtrip")
'''
# Swift assertions cannot contain a throwing autoclosure.
tests = tests.replace('assert(try String(contentsOf: child, encoding: .utf8) == "unchanged")',
                      'let content = try String(contentsOf: child, encoding: .utf8)\nassert(content == "unchanged")')
with tempfile.TemporaryDirectory(prefix='flowvision-rename-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text('import Foundation\n' + helper + tests)
    subprocess.run(['swift', str(path)], check=True)
