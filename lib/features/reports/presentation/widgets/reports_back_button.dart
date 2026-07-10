import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ReportsBackButton extends StatelessWidget {
  final String route;
  final String tooltip;

  const ReportsBackButton({
    super.key,
    this.route = '/reports',
    this.tooltip = 'Back to Reports',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () => context.go(route),
      icon: const Icon(Icons.arrow_back),
    );
  }
}
