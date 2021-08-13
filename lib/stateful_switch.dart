import 'package:flutter/material.dart';

class StatefulSwitch extends StatefulWidget {
  final bool value;
  final void Function(bool)? onChanged;
  final Color? activeColor;

  StatefulSwitch({
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  State<StatefulWidget> createState() => StatefulSwitchState(
        value: value,
        onChanged: onChanged,
        activeColor: activeColor,
      );
}

class StatefulSwitchState extends State<StatefulSwitch> {
  bool value;
  void Function(bool)? onChanged;
  Color? activeColor;

  StatefulSwitchState({
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: _onChanged,
        activeColor: activeColor,
      ).build(context);

  void _onChanged(bool newValue) {
    setState(() {
      value = newValue;
    });
    if (onChanged != null) onChanged!(value);
  }
}
