import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹出设置 PIN 的对话框。返回新 PIN；取消返回 `null`。
///
/// 修改 PIN 走的也是这里，不要求先输旧 PIN——人能站在设置页里，说明刚才
/// 已经输对过了。
Future<int?> showPinDialog(BuildContext context) =>
    showDialog<int>(context: context, builder: (_) => const PinDialog());

/// 校验一对 PIN 输入。通过返回 `null`，否则返回给用户看的原因。
///
/// 首位不能是 0：`int.parse('0123') == 123`，允许 0 开头会让两个看起来
/// 不同的 PIN 变成同一个。
String? validatePin(String pin, String confirm) {
  if (!RegExp(r'^\d{4}$').hasMatch(pin)) return 'The PIN must be 4 digits.';
  if (pin.startsWith('0')) return 'The PIN cannot start with 0.';
  if (pin != confirm) return 'The two entries do not match.';
  return null;
}

class PinDialog extends StatefulWidget {
  const PinDialog({super.key});

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final error = validatePin(_pin.text, _confirm.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(int.parse(_pin.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(const ValueKey('newPin'), _pin, 'New PIN'),
          const SizedBox(height: 8),
          _field(const ValueKey('confirmPin'), _confirm, 'Confirm PIN'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _field(Key key, TextEditingController controller, String label) =>
      TextField(
        key: key,
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
      );
}
