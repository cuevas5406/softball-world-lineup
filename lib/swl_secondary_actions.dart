import 'package:flutter/material.dart';

class SwlSecondaryActions extends StatelessWidget {
  const SwlSecondaryActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final preferred = 106 * MediaQuery.textScalerOf(context).scale(1);
        final columns = ((constraints.maxWidth + gap) / (preferred + gap))
            .floor()
            .clamp(1, children.length);
        int columnsInRow(int index) =>
            (children.length - (index ~/ columns) * columns).clamp(1, columns);
        return Wrap(
          spacing: gap,
          runSpacing: 2,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width:
                    (constraints.maxWidth - gap * (columnsInRow(i) - 1)) /
                    columnsInRow(i),
                child: children[i],
              ),
          ],
        );
      },
    );
  }
}
