import 'package:flutter/material.dart';

/// A styled card component for consistent UI appearance across the app
class StyledCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final Color? color;
  final VoidCallback? onTap;

  const StyledCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.color,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardContent = Padding(
      padding: padding ?? const EdgeInsets.all(16.0),
      child: child,
    );

    return Card(
      elevation: elevation ?? 2.0,
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      color: color ?? Theme.of(context).cardColor,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12.0),
              child: cardContent,
            )
          : cardContent,
    );
  }
}

/// A section title widget for consistent headings
class SectionTitle extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry? padding;
  final TextStyle? style;

  const SectionTitle({
    Key? key,
    required this.title,
    this.padding,
    this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
      child: Text(
        title,
        style: style ??
            Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
      ),
    );
  }
}

/// A consistent button style helper
class StyledButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool isPrimary;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;

  const StyledButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.isPrimary = true,
    this.padding,
    this.minimumSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return isPrimary
        ? ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              minimumSize: minimumSize,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              minimumSize: minimumSize,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: child,
          );
  }
}
