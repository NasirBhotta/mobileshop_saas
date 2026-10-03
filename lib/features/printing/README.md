# Optional ESC/POS development testing

This module is an opt-in Escpresso test harness. It never replaces production
PDF printing and never writes sales, inventory, ledger or Supabase data. Nothing
is registered with global application services. No connection is opened at startup.

## Files and boundaries

All new runtime files are under `lib/features/printing/`:

| File | Responsibility |
| --- | --- |
| `domain/receipt_data.dart` | Immutable printing DTO and item DTO |
| `domain/printer_adapter.dart` | Printer interface, byte-builder interface, typed results |
| `integrations/sale_receipt_mapper.dart` | Maps existing sale/settings at the application boundary |
| `escpos/escpos_config.dart` | Host, port, paper size, timeouts, dev opt-in |
| `escpos/escpos_receipt_builder.dart` | DTO to ESC/POS bytes; paper-aware text wrapping |
| `escpos/escpos_tcp_printer.dart` | Socket connection, byte send, flush, close, error handling |
| `escpos/printer_factory.dart` | Conditional IO/web export |
| `escpos/printer_factory_io.dart` | Creates adapter locally for the optional action |
| `escpos/printer_factory_stub.dart` | Safe unsupported-platform implementation |
| `presentation/dev_receipt_sample.dart` | Synthetic fixture; no transaction is recorded |
| `presentation/dev_escpos_receipt_action.dart` | Single removable development composition root/UI |
| `README.md` | Setup, limitations, testing and removal instructions |

New tests belong only to this integration:

- `test/features/printing/escpos_receipt_test.dart`
- `test/features/printing/dev_escpos_action_test.dart`

Existing files modified for this feature:

- `pubspec.yaml`: adds `esc_pos_utils_plus: ^2.0.4` to generate ESC/POS commands.
- `pubspec.lock`: records that one package. No other direct dependency added.
- `lib/features/pos/presentation/screens/receipt_reprint_screen.dart`: one import
  and one AppBar action, both for `DevEscPosReceiptAction`.

Android already declares INTERNET permission; no Android configuration changed.
The existing PDF layout/service and Windows printer-driver patch are unrelated
to this feature and are not part of its removal process.

## Data flow

```text
Existing SaleModel + ReceiptConfigurationModel (read only)
  -> SaleReceiptMapper
  -> ReceiptData
  -> PrinterAdapter.printReceipt()
  -> EscPosReceiptBuilder.build()
  -> EscPosTcpPrinterAdapter sends bytes
  -> 127.0.0.1:9100 / Escpresso
```

The sample action starts directly with `ReceiptData`. It does not load shop
settings or create a sale. For an existing invoice, select a receipt on the
Reprint Receipt screen; the mapper copies sale totals and existing item totals.
Paid/due/change presentation matches the production convention (Khata payments
are credit, not cash received). Missing invoice/date values are marked as missing,
not invented. Domain and ESC/POS implementation never import database models.

## Run Escpresso on the development computer

Install Rust/Cargo first if it is not installed. Then, in a separate terminal:

```powershell
cargo install escpresso
escpresso
```

Alternatively build the upstream source:

```powershell
git clone https://github.com/jflaflamme/escpresso.git
cd escpresso
cargo build --release
.\target\release\escpresso.exe
```

Select **58mm** in the emulator UI and keep it open. It listens on TCP port 9100.
See the [upstream Escpresso setup](https://github.com/jflaflamme/escpresso) and
[ESC/POS generator package](https://pub.dev/packages/esc_pos_utils_plus).
Receiptio is not installed or used by NIZAAM.

## Test from Windows

From the NIZAAM repository, in another terminal:

```powershell
flutter run -d windows --dart-define=NIZAAM_ESCPOS_DEV=true
```

Open POS -> Reprint Receipt -> science icon -> **Test Receipt - Dev**.
For real sale data, select/search an existing receipt and choose
**Print selected receipt - Dev**. The receipt is sent directly over TCP;
there is no Windows printer selection dialog. Check long-name wrapping, invoice,
date, item quantity/prices, discount, paid/remaining amounts, footer and cut marker.

Close Escpresso and repeat: the UI should show a printer-unavailable result,
and the existing receipt screen and normal printing remain usable.
Restart the app after changing dart-defines; hot reload does not change them.

## Test from a physical Android device

Keep Escpresso running on the computer. Connect the phone by USB, enable USB
debugging and approve the computer on the phone. In the development terminal:

```powershell
adb devices
adb -s <device-serial> reverse tcp:9100 tcp:9100
flutter run -d <device-serial> --dart-define=NIZAAM_ESCPOS_DEV=true
```

Use the same Reprint Receipt action. ADB reverse forwards the phone's
`127.0.0.1:9100` to the computer. Reapply the reverse command after reconnecting
if necessary. The application never launches ADB. To remove the forwarding:

```powershell
adb -s <device-serial> reverse --remove tcp:9100
```

## Gate and configuration

The action requires both a **debug** build and `NIZAAM_ESCPOS_DEV=true`.
It is hidden in profile/release, in normal debug runs without the flag, on web,
and on platforms other than Android/Windows. Even a release build with the flag
does not enable it. The web-safe stub prevents raw socket imports on web builds.

All defaults are in `EscPosConfig`: loopback, 9100, `PaperSize.mm58`, 3-second
connection timeout and 5-second send timeout. There are no automatic retries:
a send failure can mean partial delivery, so retry only after inspecting the
emulator. Success means socket bytes were sent, not printer acknowledgement.

This first version uses printable English/ASCII text. Long names wrap at spaces,
and unbroken identifiers split without truncation. Unsupported scripts (including
Urdu), control characters and non-finite monetary values return a generation
error. There is no silent replacement/transliteration of customer data. Add a
raster text builder later for Unicode/Urdu. Driver settings, physical cut support,
58mm printer-specific dot widths and hardware behaviour still need real-printer tests.

## Automated verification

```powershell
flutter test test/features/printing
flutter test --dart-define=NIZAAM_ESCPOS_DEV=true test/features/printing
flutter analyze lib/features/printing test/features/printing lib/features/pos/presentation/screens/receipt_reprint_screen.dart
```

Tests cover wrapping, ESC/POS command/value generation, mapper fidelity, default
UI isolation, optional UI error reporting, loopback byte delivery, missing
emulator, connection/generation/write errors and bounded send timeout/cleanup.
They do not require Escpresso or a real printer and do not connect to port 9100.

## Complete removal

1. Remove the marked `DevEscPosReceiptAction` import and AppBar action from
   `lib/features/pos/presentation/screens/receipt_reprint_screen.dart`.
2. Delete `lib/features/printing/` and `test/features/printing/`.
3. Remove `esc_pos_utils_plus` from `pubspec.yaml`.
4. Run `flutter pub get` to update the lockfile.
5. Stop passing `NIZAAM_ESCPOS_DEV`; optionally remove the ADB reverse mapping.

Do not remove existing production PDF printing, printer settings or Android
INTERNET permission. They are used independently by the application.

## Reuse for real printers

Keep `ReceiptData`, `ReceiptItem`, `PrinterAdapter`, `ReceiptByteBuilder`,
`PrinterResult`, `SaleReceiptMapper` and `EscPosReceiptBuilder`. Implement a USB
or Bluetooth adapter against the same interfaces; only transport changes.
The dev widget, sample, conditional factory and Escpresso defaults can be removed.
There is no requirement to route sale completion through any printer.
