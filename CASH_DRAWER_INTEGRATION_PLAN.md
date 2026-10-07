# Cash Drawer Integration Plan

## 1. Objective

Automatically open the physical cash drawer once a POS sale has been successfully completed through any of these payment modes:

- Cash only
- Card only
- Split payment containing cash and card

The drawer must open independently of whether the customer asks for a receipt.

The payment flow must remain safe: a drawer or printer failure must never create a second sale, lose a sale, or leave the cashier unsure whether the transaction was saved.

## 2. Required Hardware Support

The design will support two connection types.

### A. RJ11/RJ12 drawer connected to a receipt printer

The app will send a raw ESC/POS cash-drawer pulse to the selected Windows receipt printer.

Planned default command:

```text
ESC p m t1 t2
```

Hex form:

```text
1B 70 00 19 FA
```

Planned configurable values:

- Drawer pin: 2 or 5
- Pulse-on time
- Pulse-off time
- Receipt-printer name

The exact pulse timings must be confirmed with the final printer/drawer model.

### B. Standalone USB drawer adapter

A standalone USB adapter cannot be supported by one universal command because adapters use different protocols. The implementation will provide a separate adapter layer and support the protocol used by the final model.

Planned USB modes:

1. USB serial adapter / virtual COM port
2. USB HID keyboard-wedge adapter
3. Vendor-specific USB adapter

Once the model is known, one of these implementations will be enabled:

- **USB serial:** open the configured COM port and send the documented byte sequence
- **USB HID:** send the configured keyboard trigger through the Windows input API
- **Vendor USB:** call the vendor SDK/driver or send its documented raw command through a small Windows native bridge

The sale-processing and payment logic will not depend on which supported hardware method is selected.

## 3. Current Relevant Code

- `lib/presentation/screens/pos/pos_screen.dart`
  - Owns checkout/payment completion and receipt actions
- `lib/presentation/providers/sales_provider.dart`
  - Persists and completes sales
- `lib/presentation/providers/payment_provider.dart`
  - Defines cash, card, and split payment modes
- `lib/data/services/print_service.dart`
  - Builds receipt data and currently has no drawer pulse
- `lib/data/services/windows_printer_service.dart`
  - Sends raw bytes to a Windows receipt printer and can be reused for ESC/POS drawer commands
- `lib/presentation/providers/settings_provider.dart`
  - Existing application settings integration
- `lib/data/models/shop_settings.dart`
  - Planned location for persistent drawer configuration

## 4. Planned Architecture

### A. Cash drawer service

Add one central service responsible for all drawer operations.

Planned file:

```text
lib/data/services/cash_drawer_service.dart
```

Responsibilities:

- Validate whether automatic opening is enabled
- Select the configured hardware adapter
- Send exactly one drawer-open command
- Apply a short in-flight lock to prevent double taps from sending duplicate pulses
- Normalize hardware errors into safe, understandable messages
- Provide a test-open method for setup and diagnostics

The payment screen will call this service, not send printer bytes directly.

### B. Hardware adapters

Use a small adapter interface so unsupported models can be added without changing checkout logic.

Planned adapters:

```text
ReceiptPrinterDrawerAdapter
UsbSerialDrawerAdapter
UsbHidDrawerAdapter
VendorUsbDrawerAdapter
```

The receipt-printer adapter can be implemented first because it uses the existing Windows raw-printer transport. USB adapters will be completed after the adapter make/model and protocol are known.

### C. Payment integration

Add drawer opening only after the sale has been successfully persisted.

Required order:

1. Validate cart and payment totals
2. Persist the sale
3. Confirm sale completion succeeded
4. Clear checkout UI/processing state as appropriate
5. Attempt one drawer-open command
6. If the command fails, keep the sale completed and show a drawer-only retry action

Important behavior:

- A split sale sends one drawer pulse after the combined payment is complete
- The drawer does not open separately for the cash and card portions
- No drawer command is sent before database success
- No drawer command is sent for held, voided, cancelled, refunded, or failed sales
- Receipt printing is not required
- A drawer failure never calls the sale-processing method again

### D. Exactly-once protection

A physical drawer normally has no open/closed acknowledgement, so software can guarantee one command attempt per completed checkout, not physically confirm that the drawer moved.

Protection will include:

- One completed-sale ID per drawer event
- One in-flight drawer lock
- A persisted drawer event/status tied to the sale ID
- A unique constraint preventing multiple automatic events for the same sale
- No automatic retry after a command has already been sent successfully
- Manual drawer-only retry after a clear hardware failure

This prevents a receipt retry, screen refresh, or duplicate button press from generating an unintended second drawer event.

## 5. Planned Settings

Add these settings under Printer/Drawer settings:

| Setting | Purpose |
|---|---|
| Enable automatic cash drawer | Enables opening after completed payment |
| Connection type | Receipt printer, USB serial, USB HID, or vendor USB |
| Receipt printer | Windows printer used for the RJ11/RJ12 pulse |
| Drawer pin | Pin 2 or pin 5 |
| Pulse-on time | ESC/POS drawer pulse duration |
| Pulse-off time | Delay between pulses |
| USB COM port | Port for a serial adapter |
| USB baud rate | Serial adapter communication speed |
| USB trigger keys | HID keyboard sequence |
| USB command bytes | Validated hexadecimal command for a supported adapter |
| Last test result | Last successful command attempt or failure reason |

The drawer settings must be validated before saving. Arbitrary shell commands will not be accepted or executed.

## 6. User Experience

### Successful payment

1. Sale is saved.
2. One drawer-open command is sent.
3. Checkout completes normally.

The app should not claim that physical opening was verified because most drawer hardware provides no open/closed sensor feedback.

### Drawer command failure

The sale remains completed and the screen shows:

```text
Sale completed, but the cash drawer did not receive the open command.
Check the printer/drawer connection.
```

Available actions:

- **Retry drawer only**
- **Continue without opening**

The retry action must never process or duplicate the sale.

### Settings diagnostics

Add a **Test cash drawer** button.

The test should:

- Require explicit operator action
- Use the currently selected connection
- Display whether the command was sent or failed
- Not create a test sale
- Not affect inventory, sales totals, or backups

## 7. Error Handling

Handle the following cases safely:

- Receipt printer is offline
- Receipt printer name is missing or changed
- Printer driver rejects raw data
- USB adapter is disconnected
- USB serial port is unavailable or changed
- HID trigger cannot be sent
- Vendor driver/SDK fails
- Drawer cable is disconnected
- Access permission is denied
- Command is sent but the drawer mechanism is jammed
- App closes immediately after a completed sale

A drawer failure will be logged without exposing payment, customer, or other sensitive data.

## 8. Files Expected to Change During Implementation

New files:

```text
lib/data/services/cash_drawer_service.dart
lib/data/services/drawer_adapters/...
tests for drawer commands and payment triggering
```

Existing files likely to change:

```text
lib/presentation/screens/pos/pos_screen.dart
lib/presentation/providers/sales_provider.dart
lib/presentation/providers/settings_provider.dart
lib/data/models/shop_settings.dart
lib/data/services/print_service.dart
lib/data/services/windows_printer_service.dart
lib/data/database/database_service.dart
lib/presentation/screens/settings/settings_screen.dart
```

Possible Windows-native files, only if required by the final USB adapter:

```text
windows/runner/flutter_window.cpp
windows/runner/CMakeLists.txt
```

## 9. Testing Plan

### Automated tests

- Cash payment sends one drawer event
- Card payment sends one drawer event
- Split payment sends one drawer event
- Split payment does not send two events
- Failed sale sends no drawer event
- Held/cancelled sale sends no drawer event
- Receipt skipped still sends the drawer command
- Receipt failure does not undo the sale or trigger an unsafe sale retry
- Double tap sends only one event
- Retry-drawer does not create another sale/event
- Standard ESC/POS command bytes are correct
- Pin 2 and pin 5 command variants are correct
- Invalid settings are rejected
- USB serial/HID command encoding is correct
- Service handles offline/disconnected hardware without crashing the app
- Existing database/settings migrations remain backward compatible

### Physical Windows tests

Test on the exact client hardware:

- Cash only opens once
- Card only opens once
- Cash plus card opens once
- Complete without receipt opens the drawer
- Print receipt opens the drawer once
- Receipt printer offline does not lose the sale
- USB adapter disconnect/reconnect behavior
- Windows restart and USB port reconnection
- Rapid successive sales
- Cash drawer cable removal
- Multiple Windows printers
- Installer upgrade preserves drawer settings and sales data

## 10. Client Delivery Checklist

Before delivery:

- Confirm drawer make and model
- Confirm whether it connects to the printer or standalone USB adapter
- Confirm RJ11/RJ12 pin, if applicable
- Confirm printer make and model
- Confirm printer driver is installed under its exact Windows name
- Confirm drawer cable routing and connector orientation
- Confirm USB adapter protocol/driver
- Run **Test cash drawer** successfully at least three times
- Run all automated tests
- Run Flutter static analysis
- Build and smoke-test the Windows release installer
- Test payment flows on the client's actual computer
- Test upgrade from the currently installed version
- Verify database backup/restore still works

## 11. Information Required When the Model Is Known

Complete this section later:

```text
Cash drawer make:
Cash drawer model:
Connection type: RJ11/RJ12 printer / USB serial / USB HID / vendor USB
Receipt printer make:
Receipt printer model:
Drawer pin: 2 / 5
Recommended pulse-on time:
Recommended pulse-off time:
USB adapter make/model:
USB COM port and baud rate, if applicable:
HID trigger sequence, if applicable:
Required raw command bytes, if applicable:
Driver or SDK required:
Windows printer name:
```

## 12. Delivery Readiness Rule

The feature must not be marked production-ready until it has passed the automated tests and physical tests on the exact receipt printer, drawer, and USB adapter model intended for the client.

The software can be made reliable across all supported connection types, but final command bytes, pin selection, pulse timing, and USB protocol cannot be confirmed while the hardware model is unknown.

## 13. Current Status

- Cash drawer support is not currently implemented
- Required behavior is defined in this plan
- Cash, card, and split payment behavior is confirmed
- Receipt-printer/RJ11/RJ12 support can be implemented first
- Standalone USB adapter implementation requires the adapter model and its command protocol
- No production hardware claim should be made until the physical acceptance tests pass
