import 'package:flutter/material.dart';

/// Shared desktop spacing and surfaces; no changes to data or chart scaling.
class OeWorkspace extends StatelessWidget {
  final Widget child;
  const OeWorkspace({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1560),
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),),
      );
}

class OeWorkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const OeWorkCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),});
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, child: Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .6))),
    child: Padding(padding: padding, child: child),
  ),);

}

class OeTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const OeTag(this.label, {super.key, this.icon = Icons.info_outline});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
              child:
                  Text(label, style: Theme.of(context).textTheme.labelMedium),),
        ],),
      );
}
