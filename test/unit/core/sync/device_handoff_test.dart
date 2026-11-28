import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/device_handoff.dart';

/// The handoff is safe because of what the server cannot do, so most of this
/// plays the server: swapping a key, moving a message, replaying one.
void main() {
  const userId = 'user-1';
  const accountKey = 'YWNjb3VudC1rZXktYWNjb3VudC1rZXktYWNjb3VudC0=';

  DateTime soon() => DateTime.now().add(const Duration(minutes: 3));

  Future<HandoffDisplay> display({
    bool gives = true,
    String id = 'handoff-1',
  }) => DeviceHandoff.display(
    id: id,
    userId: userId,
    gives: gives,
    expiresAt: soon(),
  );

  /// The code as a camera reads it.
  HandoffInvite scanned(HandoffDisplay display) =>
      HandoffInvite.decode(display.invite.encode());

  group('the two directions', () {
    test('a phone scans the desktop that holds the key', () async {
      final desktop = await display();
      final phone = await DeviceHandoff.scan(scanned(desktop), userId: userId);

      await desktop.acceptOffer(await phone.offer(''));
      final answer = await desktop.answer(accountKey);

      expect(await phone.openAnswer(answer), accountKey);
    });

    test('a phone that holds the key scans a new desktop', () async {
      final desktop = await display(gives: false);
      final phone = await DeviceHandoff.scan(scanned(desktop), userId: userId);

      expect(
        await desktop.acceptOffer(await phone.offer(accountKey)),
        accountKey,
      );
    });
  });

  group('what the server cannot do', () {
    test('swap the scanner\'s public key for its own', () async {
      // The move that would make the desktop seal the key to the server.
      final desktop = await display();
      final phone = await DeviceHandoff.scan(scanned(desktop), userId: userId);
      final server = await DeviceHandoff.scan(scanned(desktop), userId: userId);

      final offer = jsonDecode(await phone.offer('')) as Map<String, dynamic>;
      final serversOwn =
          jsonDecode(await server.offer('')) as Map<String, dynamic>;

      await expectLater(
        desktop.acceptOffer(jsonEncode({...offer, 'pk': serversOwn['pk']})),
        throwsA(isA<HandoffException>()),
      );
      expect(() => desktop.answer(accountKey), throwsStateError);
    });

    test('make an offer of its own without the code', () async {
      // It knows the mailbox and the account. It does not know the secret.
      final desktop = await display();
      final real = scanned(desktop);
      final guessed = HandoffInvite(
        id: real.id,
        userId: real.userId,
        publicKey: real.publicKey,
        secret: (await display()).invite.secret,
        displayerGives: real.displayerGives,
        expiresAt: real.expiresAt,
      );
      final server = await DeviceHandoff.scan(guessed, userId: userId);

      await expectLater(
        desktop.acceptOffer(await server.offer('')),
        throwsA(isA<HandoffException>()),
      );
    });

    test('play an offer into another handoff', () async {
      final first = await display();
      final phone = await DeviceHandoff.scan(scanned(first), userId: userId);
      final offer = await phone.offer(accountKey);

      final second = await display(id: 'handoff-2');

      await expectLater(
        second.acceptOffer(offer),
        throwsA(isA<HandoffException>()),
      );
    });

    test('hand the scanner back its own message as the answer', () async {
      final desktop = await display();
      final phone = await DeviceHandoff.scan(scanned(desktop), userId: userId);
      final offer = jsonDecode(await phone.offer('')) as Map<String, dynamic>;

      await expectLater(
        phone.openAnswer(offer['box'] as String),
        throwsA(isA<HandoffException>()),
      );
    });

    test('alter the answer', () async {
      final desktop = await display();
      final phone = await DeviceHandoff.scan(scanned(desktop), userId: userId);
      await desktop.acceptOffer(await phone.offer(''));

      final answer = base64.decode(await desktop.answer(accountKey));
      answer[answer.length - 1] ^= 1;

      await expectLater(
        phone.openAnswer(base64.encode(answer)),
        throwsA(isA<HandoffException>()),
      );
    });
  });

  group('a code that should not be used', () {
    test('from another account', () async {
      final desktop = await display();

      await expectLater(
        DeviceHandoff.scan(scanned(desktop), userId: 'someone-else'),
        throwsA(isA<HandoffException>()),
      );
    });

    test('that has run out', () async {
      final desktop = await DeviceHandoff.display(
        id: 'handoff-1',
        userId: userId,
        gives: true,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      await expectLater(
        DeviceHandoff.scan(scanned(desktop), userId: userId),
        throwsA(isA<HandoffException>()),
      );
    });

    test('that is some other QR code', () {
      for (final raw in [
        'https://shellvibe.dev',
        '{"t":"something-else"}',
        '{"t":"shellvibe-handoff","v":1,"id":"x","u":"y","pk":"AA","s":"AA",'
            '"give":true,"exp":1}',
      ]) {
        expect(
          () => HandoffInvite.decode(raw),
          throwsA(isA<HandoffException>()),
          reason: raw,
        );
      }
    });
  });
}
