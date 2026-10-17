// bKash / Nagad messages -> suggested entries, read on the phone (services/sms.dart),
// and how the review plans each one (screens/sms_review_sheet.dart).
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/sms_review_sheet.dart';
import 'package:catalyst/services/sms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

final _at = DateTime(2026, 10, 17, 22, 0);

SmsTxn? _read(String body, {String from = 'bKash'}) => parseSms(body, address: from, received: _at, smsId: '42');

void main() {
  group('bKash', () {
    test('money received', () {
      final s = _read('You have received Tk 1,500.00 from 01712345678. Ref Rent. Fee Tk 0.00. Balance Tk 3,250.50. TrxID BJ71KL2M9P at 17/10/2026 14:32')!;
      expect(s.action, SmsAction.received);
      expect(s.isIncome, isTrue);
      expect(s.amount, 1500);
      expect(s.fee, 0);
      expect(s.party, '…5678'); // a phone number keeps only its last digits
      expect(s.key, 'bkash:BJ71KL2M9P');
      expect(s.when, DateTime(2026, 10, 17, 14, 32));
      expect(s.provider, 'bKash');
      expect(smsNote(s), 'Received from …5678');
    });

    test('a payment to a shop keeps the shop name', () {
      final s = _read('Payment Tk 350.00 to Daraz (01812345678) successful. Fee Tk 0.00. Balance Tk 2,900.50. TrxID BJ72AB3C4D at 17/10/2026 15:01')!;
      expect(s.action, SmsAction.payment);
      expect(s.isExpense, isTrue);
      expect(s.amount, 350);
      expect(s.party, 'Daraz');
      expect(smsNote(s), 'Payment to Daraz');
    });

    test('send money with a fee', () {
      final s = _read('Send Money Tk 500.00 to 01912345678 successful. Ref gift. Fee Tk 5.00. Balance Tk 2,395.50. TrxID BJ73XY5Z6W at 17/10/2026 16:10')!;
      expect(s.action, SmsAction.sendMoney);
      expect(s.amount, 500);
      expect(s.fee, 5);
    });

    test('cash out and cash in are transfers', () {
      final out = _read('Cash Out Tk 1,000.00 to 01612345678 successful. Fee Tk 18.50. Balance Tk 1,377.00. TrxID BJ74QR7S8T at 17/10/2026 18:45')!;
      expect(out.action, SmsAction.cashOut);
      expect(out.isTransfer, isTrue);
      expect(out.fee, 18.5);
      final cashIn = _read('Cash In Tk 2,000.00 from 01512345678 successful. Fee Tk 0.00. Balance Tk 3,377.00. TrxID BJ75UV9W0X at 17/10/2026 19:00')!;
      expect(cashIn.action, SmsAction.cashIn);
      expect(cashIn.amount, 2000);
    });

    test('mobile recharge', () {
      final s = _read('Mobile Recharge Tk 50.00 to 01712345678 successful. Fee Tk 0.00. Balance Tk 3,327.00. TrxID BJ76YZ1A2B at 17/10/2026 20:00')!;
      expect(s.action, SmsAction.recharge);
      expect(smsNote(s), 'Mobile recharge');
    });

    test('a Bengali message with Bengali digits', () {
      final s = _read('আপনি ০১৭১২৩৪৫৬৭৮ থেকে ৳৫০০.০০ পেয়েছেন। ফি ৳০.০০। ব্যালেন্স ৳১,২০০.০০। TrxID BJ77CD3E4F 17/10/2026 21:15')!;
      expect(s.action, SmsAction.received);
      expect(s.amount, 500);
      expect(s.when, DateTime(2026, 10, 17, 21, 15));
    });

    test('codes, failures and offers are not entries', () {
      expect(_read('Your bKash verification code is 123456. Do not share it with anyone.'), isNull);
      expect(_read('Payment of Tk 200.00 to Pathao failed due to insufficient balance. TrxID BJ78EF5G6H'), isNull);
      expect(_read('Get 10% cashback on Daraz! Offer valid till 31 Oct.'), isNull);
      expect(_read('Your OTP for Tk 500.00 payment is 9911'), isNull);
    });

    test('a date that reads oddly falls back to when the message arrived', () {
      final s = _read('Payment Tk 99.00 to Shop successful. TrxID BJ79IJ7K8L at 03/04/2025 10:00')!;
      expect(s.when, _at);
    });
  });

  group('Nagad', () {
    test('money received, labelled fields', () {
      final s = _read('Money Received.\nAmount: Tk 300.00\nSender: 01812345678\nRef: lunch\nTxnID: 7A2B3C4D\nBalance: Tk 1,050.00\n17/10/2026 13:20', from: 'NAGAD')!;
      expect(s.provider, 'Nagad');
      expect(s.action, SmsAction.received);
      expect(s.amount, 300);
      expect(s.party, '…5678');
      expect(s.key, 'nagad:7A2B3C4D');
    });

    test('cash out with a charge', () {
      final s = _read('Cash Out Successful.\nAmount: Tk 1000.00\nUddokta: 01712345678\nCharge: Tk 14.95\nTxnID: 7E5F6G7H\nBalance: Tk 35.05\n17/10/2026 10:05', from: 'NAGAD')!;
      expect(s.action, SmsAction.cashOut);
      expect(s.amount, 1000);
      expect(s.fee, 14.95);
    });

    test('a merchant payment', () {
      final s = _read('Payment Successful.\nAmount: Tk 450.00\nMerchant: Shwapno\nTxnID: 7J8K9L0M\nBalance: Tk 600.00\n17/10/2026 12:00', from: 'Nagad')!;
      expect(s.action, SmsAction.payment);
      expect(s.party, 'Shwapno');
    });
  });

  group('capture', () {
    setUp(() => SharedPreferences.setMockInitialValues({'sms:on': true, 'sms:since': 0}));
    tearDown(() => SmsCapture.readInbox = (since) async => const []);

    test('new messages once; nothing again after they are handled', () async {
      SmsCapture.readInbox = (since) async => [
            {'id': '1', 'address': 'bKash', 'date': _at.millisecondsSinceEpoch, 'body': 'Payment Tk 350.00 to Daraz successful. Fee Tk 0.00. TrxID BJ72AB3C4D at 17/10/2026 15:01'},
            {'id': '2', 'address': 'bKash', 'date': _at.millisecondsSinceEpoch, 'body': 'Your bKash verification code is 123456.'},
            // the same transaction again (a re-sent message): one suggestion
            {'id': '3', 'address': 'bKash', 'date': _at.millisecondsSinceEpoch, 'body': 'Payment Tk 350.00 to Daraz successful. Fee Tk 0.00. TrxID BJ72AB3C4D at 17/10/2026 15:01'},
          ];
      final first = await SmsCapture.pending();
      expect(first.length, 1);
      await SmsCapture.markSeen(first);
      expect(await SmsCapture.pending(), isEmpty);
    });

    test('off means nothing is read', () async {
      SharedPreferences.setMockInitialValues({'sms:on': false});
      var read = false;
      SmsCapture.readInbox = (since) async {
        read = true;
        return const [];
      };
      expect(await SmsCapture.pending(), isEmpty);
      expect(read, isFalse);
    });
  });

  group('review plan', () {
    const cash = Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#000000', openingBalance: 0, sort: 0, archived: false);
    const bkash = Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#000000', openingBalance: 0, sort: 1, archived: false);

    test('spending goes in the bKash wallet; a cash out moves bKash -> Cash', () {
      final app = FakeApp()
        ..walletsReady = true
        ..wallets = [cash, bkash];
      final pay = planSms(_read('Payment Tk 350.00 to Daraz successful. TrxID BJ72AB3C4D at 17/10/2026 15:01')!, app);
      expect(pay.kind, Kind.expense);
      expect(pay.wallet?.id, 'bk');
      final out = planSms(_read('Cash Out Tk 1,000.00 to 01612345678 successful. Fee Tk 18.50. TrxID BJ74QR7S8T at 17/10/2026 18:45')!, app);
      expect(out.kind, isNull);
      expect(out.from?.id, 'bk');
      expect(out.to?.id, 'cash');
    });

    test('without a Bank wallet, add money from a bank can\'t be recorded', () {
      final app = FakeApp()
        ..walletsReady = true
        ..wallets = [cash, bkash];
      final plan = planSms(_read('Add Money Tk 5,000.00 from DBBL successful. TrxID BJ80MN9O0P at 17/10/2026 11:00')!, app);
      expect(plan.ok, isFalse);
    });
  });
}
