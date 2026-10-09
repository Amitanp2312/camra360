import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/services/upload_queue.dart';

void main() {
  test('undo before the upload sends nothing remote', () {
    expect(
      nextSendAction(cancelled: true, uploaded: false, inserted: false),
      SendAction.stop,
    );
  });

  test('a send uploads, then inserts, then stops', () {
    expect(
      nextSendAction(cancelled: false, uploaded: false, inserted: false),
      SendAction.upload,
    );
    expect(
      nextSendAction(cancelled: false, uploaded: true, inserted: false),
      SendAction.insertRow,
    );
    expect(
      nextSendAction(cancelled: false, uploaded: true, inserted: true),
      SendAction.stop,
    );
  });

  test('undo after the bytes are stored deletes the remote copy', () {
    expect(
      nextSendAction(cancelled: true, uploaded: true, inserted: false),
      SendAction.deleteRemote,
    );
    expect(
      nextSendAction(cancelled: true, uploaded: true, inserted: true),
      SendAction.deleteRemote,
    );
  });
}
