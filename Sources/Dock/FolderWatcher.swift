import Foundation

/// 폴더 내용이 바뀌면 알려준다. Finder에서 보관 폴더에 직접 파일을 넣어도 독이 따라잡게 하는 용도.
final class FolderWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    func start(url: URL, handler: @MainActor @escaping () -> Void) {
        stop()

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )
        source.setEventHandler {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler() }
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        source?.cancel()
    }
}
