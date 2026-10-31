import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('checker', Path(__file__).parents[1] / 'check_design_tokens.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def rules(source):
    return [line.split(': ')[1] for line in checker.violations(Path('View.swift'), source)]


class DesignTokenCheckTests(unittest.TestCase):
    def test_flags_raw_visual_values(self):
        self.assertEqual(rules('Text("a").foregroundStyle(.red)'), ['system-color'])
        self.assertEqual(rules('let tint = Color.white'), ['system-color'])
        self.assertEqual(rules('let tint = Color(hex: 0x123456)'), ['raw-color'])
        self.assertEqual(rules('withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {'), ['raw-spring'])
        self.assertEqual(rules('Text("a").font(.caption)'), ['system-text-style'])
        self.assertEqual(rules('Image(systemName: "x").font(.system(size: 12, weight: .bold))'), ['system-font'])
        self.assertEqual(rules('.clipShape(RoundedRectangle(cornerRadius: 12))'), ['corner-style'])

    def test_accepts_tokens_and_unrelated_names(self):
        self.assertEqual(rules('Text("a").foregroundStyle(AngroveTheme.Colors.accentRed)'), [])
        self.assertEqual(rules('Image(systemName: "x").angroveIcon(.small, .strong)'), [])
        self.assertEqual(rules('withAnimation(.springStandard) {'), [])
        self.assertEqual(rules('.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))'), [])
        self.assertEqual(rules('case .red: return "Red"'), [])
        self.assertEqual(rules('let label = "Color.white"  // .font(.caption)'), [])

    def test_continuous_style_on_the_next_line_passes(self):
        self.assertEqual(rules('RoundedRectangle(cornerRadius: 12,\n    style: .continuous)'), [])
        self.assertEqual(rules('RoundedRectangle(\n    cornerRadius: 12, // matches the chip\n    style: .continuous\n)'), [])

    def test_flags_calls_split_across_lines(self):
        self.assertEqual(rules('let c = Color(\n    red: 0.1, green: 0.2, blue: 0.3)'), ['raw-color'])
        self.assertEqual(rules('Text("a").font(\n    .system(size: 12))'), ['system-font'])
        self.assertEqual(rules('Text("a").foregroundStyle(\n    .red)'), ['system-color'])
        self.assertEqual(rules('.background(\n    in: RoundedRectangle(\n        cornerRadius: 12\n    )\n)'), ['corner-style'])
        self.assertEqual(rules('.background(fill)\n.cornerRadius(12)'), ['corner-style'])

    def test_ignores_comments_and_strings_across_lines(self):
        self.assertEqual(rules('/* Color.red\n   /* nested */ .font(.caption) */\nlet a = 1'), [])
        self.assertEqual(rules('let s = """\n    Color.red .font(.system(size: 1))\n    """\nlet b = 2'), [])
        self.assertEqual(rules('let s = #"Color.red \\" .spring("#'), [])
        self.assertEqual(rules('Text("a").font(/* body font */ .system(size: 12))'), ['system-font'])

    def test_flags_system_colors_inside_nested_arguments(self):
        source = '.foregroundStyle(active ? AngroveTheme.Colors.lightGreen.opacity(0.5) : .red)'
        self.assertEqual(rules(source), ['system-color'])
        self.assertEqual(rules('.init(color: .black, location: 0.2)'), ['system-color'])
        self.assertEqual(rules('.frame(alignment: .center).padding(.horizontal)'), [])
        self.assertEqual(rules('.init(color: edge ? .clear : .red, location: 1)'), ['system-color'])
        self.assertEqual(rules('LinearGradient(colors: [AngroveTheme.Colors.mask, flag ? .clear : .black], startPoint: .top)'),
                         ['system-color'])
        self.assertEqual(rules('.init(color: AngroveTheme.Colors.mask, location: edge ? .zero : .one)'), [])

    def test_checks_the_style_argument_itself(self):
        self.assertEqual(rules('RoundedRectangle(cornerRadius: metrics.continuousRadius, style: .circular)'),
                         ['corner-style'])
        self.assertEqual(rules('RoundedRectangle(cornerRadius: metrics.continuousRadius)'), ['corner-style'])

    def test_reports_the_line_of_the_offending_value(self):
        found = checker.violations(Path('View.swift'), 'Text("a")\n    .foregroundStyle(\n        .red)')
        self.assertEqual([line.split(': ')[0] for line in found], ['View.swift:3'])

    def test_allow_marker_and_design_system_folders_are_exempt(self):
        self.assertEqual(rules('.fill(.white) // design-tokens: allow luminance mask'), [])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ('Shared/DesignSystem', 'Shared/Features'):
                (root / folder).mkdir(parents=True)
            (root / 'Shared/DesignSystem/Theme.swift').write_text('let c = Color(hex: 0x123456)\n')
            (root / 'Shared/Features/View.swift').write_text('let c = AngroveTheme.Colors.canvas\n')
            self.assertEqual(checker.main(root), 0)
            (root / 'Shared/Features/View.swift').write_text('let c = Color(hex: 0x123456)\n')
            self.assertEqual(checker.main(root), 1)


if __name__ == '__main__':
    unittest.main()
