import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner registers and forwards the Supabase auth callback', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('L"io.supabase.mobileshop"'));
    expect(source, contains('HKEY_CURRENT_USER'));
    expect(source, contains('L"URL Protocol"'));
    expect(source, contains('L"\\\" \\\"%1\\\""'));
    expect(source, contains('SendAppLinkToInstance()'));
    expect(
      source.indexOf('RegisterAuthProtocol();'),
      lessThan(source.indexOf('SendAppLinkToInstance()')),
    );
  });
}
