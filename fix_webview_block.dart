import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();

  // The bad block uses literal \r (two chars: backslash + r) instead of proper line endings
  // Find and replace the entire bad block with the clean version
  final badBlock = "if (_isWebMode) ...[\\" + "r\r\n" +
    "              Positioned.fill(\\" + "r\r\n" +
    "                bottom: 160, // Deja espacio para el mini-player + bottom nav\\" + "r\r\n" +
    "                child: AnnotatedRegion<SystemUiOverlayStyle>(\\" + "r\r\n" +
    "                  value: _isDarkMode\\" + "r\r\n" +
    "                      ? SystemUiOverlayStyle.light.copyWith(\\" + "r\r\n" +
    "                          statusBarColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarDividerColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarContrastEnforced: false,\\" + "r\r\n" +
    "                        )\\" + "r\r\n" +
    "                      : SystemUiOverlayStyle.dark.copyWith(\\" + "r\r\n" +
    "                          statusBarColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarDividerColor: Colors.transparent,\\" + "r\r\n" +
    "                          systemNavigationBarContrastEnforced: false,\\" + "r\r\n" +
    "                        ),\\" + "r\r\n" +
    "                  child: _buildWebView(),\\" + "r\r\n" +
    "                ),\\" + "r\r\n" +
    "              ),\\" + "r\r\n" +
    "            ],";

  const goodBlock = '''if (_isWebMode) ...[
              Positioned.fill(
                bottom: 160, // Deja espacio para el mini-player + bottom nav
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: _isDarkMode
                      ? SystemUiOverlayStyle.light.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        )
                      : SystemUiOverlayStyle.dark.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        ),
                  child: _buildWebView(),
                ),
              ),
            ],''';

  if (content.contains(badBlock)) {
    content = content.replaceFirst(badBlock, goodBlock);
    file.writeAsStringSync(content);
    print('Fixed successfully.');
  } else {
    print('Bad block not found. Trying alternate approach...');
    // Try replacing any line that contains a literal backslash-r at end
    final lines = content.split('\n');
    final fixed = lines.map((line) => line.replaceAll('\\r', '')).join('\n');
    file.writeAsStringSync(fixed);
    print('Applied alternate fix (removed all \\\\r).');
  }
}
