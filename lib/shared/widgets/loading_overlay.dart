import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    required this.isLoading,
    required this.child,
    super.key,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          const Positioned.fill(
            child: Stack(
              children: [
                ModalBarrier(dismissible: false, color: Color(0x66000000)),
                Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
      ],
    );
  }
}
