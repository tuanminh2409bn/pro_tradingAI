import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

enum ChartTool {
  pointer,
  crosshair,
  trendLine,
  horizontalLine,
  verticalLine,
  rectangle,
  fibonacci,
  text,
  ruler,
  magnet,
  eraser,
}

class ChartToolsSidebar extends StatefulWidget {
  final ChartTool activeTool;
  final ValueChanged<ChartTool> onToolChanged;

  const ChartToolsSidebar({
    super.key,
    required this.activeTool,
    required this.onToolChanged,
  });

  @override
  State<ChartToolsSidebar> createState() => _ChartToolsSidebarState();
}

class _ChartToolsSidebarState extends State<ChartToolsSidebar> {
  static const List<_ToolGroup> _groups = [
    // Group 1 – Cursor
    _ToolGroup(tools: [
      _ToolDef(tool: ChartTool.pointer,       icon: Icons.mouse,             label: 'Pointer (V)'),
      _ToolDef(tool: ChartTool.crosshair,     icon: Icons.add,               label: 'Crosshair (+)'),
    ]),
    // Group 2 – Drawing Lines
    _ToolGroup(tools: [
      _ToolDef(tool: ChartTool.trendLine,     icon: Icons.show_chart,        label: 'Trend Line (T)'),
      _ToolDef(tool: ChartTool.horizontalLine,icon: Icons.horizontal_rule,   label: 'Horizontal Line (H)'),
      _ToolDef(tool: ChartTool.verticalLine,  icon: Icons.vertical_align_center, label: 'Vertical Line'),
      _ToolDef(tool: ChartTool.rectangle,     icon: Icons.crop_square,       label: 'Rectangle (R)'),
    ]),
    // Group 3 – Analysis Tools
    _ToolGroup(tools: [
      _ToolDef(tool: ChartTool.fibonacci,     icon: Icons.bar_chart,         label: 'Fibonacci Retracement (F)'),
      _ToolDef(tool: ChartTool.ruler,         icon: Icons.straighten,        label: 'Ruler / Measure'),
    ]),
    // Group 4 – Annotation
    _ToolGroup(tools: [
      _ToolDef(tool: ChartTool.text,          icon: Icons.text_fields,       label: 'Text Label'),
    ]),
    // Group 5 – Utilities
    _ToolGroup(tools: [
      _ToolDef(tool: ChartTool.magnet,        icon: Icons.adjust,            label: 'Magnet (Snap to OHLC)'),
      _ToolDef(tool: ChartTool.eraser,        icon: Icons.delete_outline,    label: 'Eraser'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: _groups.expand((group) {
            final buttons = group.tools.map((def) => _buildButton(def)).toList();
            return [
              ...buttons,
              Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.white.withValues(alpha: 0.05)),
            ];
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildButton(_ToolDef def) {
    final isActive = widget.activeTool == def.tool;
    return Tooltip(
      message: def.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1d20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      textStyle: const TextStyle(color: Colors.white70, fontSize: 12),
      child: InkWell(
        onTap: () => widget.onToolChanged(def.tool),
        borderRadius: BorderRadius.circular(4),
        hoverColor: AppColors.primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Icon(
              def.icon,
              size: 16,
              color: isActive ? AppColors.primary : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolGroup {
  final List<_ToolDef> tools;
  const _ToolGroup({required this.tools});
}

class _ToolDef {
  final ChartTool tool;
  final IconData icon;
  final String label;
  const _ToolDef({required this.tool, required this.icon, required this.label});
}
