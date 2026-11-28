import 'package:flutter/material.dart';

class SwlSecondaryActions extends StatelessWidget {
  const SwlSecondaryActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final preferred = 106 * MediaQuery.textScalerOf(context).scale(1);
          final columns = ((constraints.maxWidth + gap) / (preferred + gap))
              .floor()
              .clamp(1, children.length);
          return Column(
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: [
              for (var start = 0; start < children.length; start += columns)
                IntrinsicHeight(
                  child: Row(
                    spacing: gap,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final child in children.skip(start).take(columns))
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: double.infinity,
                              child: child,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class SwlSecondaryAction extends StatelessWidget {
  const SwlSecondaryAction({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.amber,
      side: const BorderSide(color: Colors.amber, width: 1),
      minimumSize: const Size(48, 40),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    onPressed: onPressed,
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, height: 1.1),
    ),
  );
}
