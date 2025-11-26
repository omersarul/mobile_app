import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7DFF),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Neural Style Transfer',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          backgroundColor: scheme.surface.withOpacity(0.75),
          foregroundColor: scheme.onSurface,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

/// Uygulama kabuğu: alt menü + sayfalar arası state yönetimi
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Oturum state’i: fotoğraf seçimleri ve üretilen sonuçlar
  File? lastContent;
  File? lastStyle;
  final List<Uint8List> historyResults = [];

  // Stil Değişimi sayfası sonuç ürettiğinde çağrılacak
  void _onNewResult(Uint8List bytes, {File? usedContent, File? usedStyle}) {
    setState(() {
      historyResults.insert(0, bytes);
      lastContent = usedContent ?? lastContent;
      lastStyle = usedStyle ?? lastStyle;
      _index = 2; // üretim sonrası Geçmiş sekmesine geç
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      StyleTransferPage(
        onResult: _onNewResult,
        onContentPicked: (f) => setState(() => lastContent = f),
        onStylePicked: (f) => setState(() => lastStyle = f),
      ),
      PhotosPage(content: lastContent, style: lastStyle),
      HistoryPage(history: historyResults),
    ];

    return Stack(
      children: [
        const _BlueGradientBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: IndexedStack(index: _index, children: pages),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.brush_outlined),
                selectedIcon: Icon(Icons.brush),
                label: 'Stil',
              ),
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Fotoğraflar',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'Geçmiş',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Arka plan gradyanı
class _BlueGradientBackground extends StatelessWidget {
  const _BlueGradientBackground();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F0FF), Color(0xFFD6E4FF), Color(0xFFBED3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/* ===================== 1) STİL DEĞİŞİMİ SAYFASI ===================== */

class StyleTransferPage extends StatefulWidget {
  const StyleTransferPage({
    super.key,
    required this.onResult,
    required this.onContentPicked,
    required this.onStylePicked,
  });

  final void Function(
    Uint8List resultBytes, {
    File? usedContent,
    File? usedStyle,
  })
  onResult;
  final void Function(File f) onContentPicked;
  final void Function(File f) onStylePicked;

  @override
  State<StyleTransferPage> createState() => _StyleTransferPageState();
}

class _StyleTransferPageState extends State<StyleTransferPage> {
  final picker = ImagePicker();
  File? content, style;
  Uint8List? resultBytes;
  bool loading = false;

  // Debug: masaüstü -> 127.0.0.1, Android emülatör -> 10.0.2.2
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://192.168.0.152:5000',
  );

  Future<void> _pick(bool isContent) async {
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (x != null) {
      final f = File(x.path);
      setState(() {
        if (isContent) {
          content = f;
          widget.onContentPicked(f);
        } else {
          style = f;
          widget.onStylePicked(f);
        }
      });
    }
  }

  Future<void> _stylize() async {
    if (content == null || style == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Önce iki görsel seç')));
      return;
    }
    setState(() {
      loading = true;
      resultBytes = null;
    });

    final uri = Uri.parse('$baseUrl/stylize');
    try {
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('content', content!.path))
        ..files.add(await http.MultipartFile.fromPath('style', style!.path))
        ..fields['max_dim'] = '384'; // daha hızlı sonuç için

      final streamed = await req.send().timeout(const Duration(seconds: 180));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        setState(() => resultBytes = bytes);
        widget.onResult(bytes, usedContent: content, usedStyle: style);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sunucu hatası: ${resp.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ağ hatası: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _imageCard(content, 'Content seç', () => _pick(true)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _imageCard(style, 'Style seç', () => _pick(false)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loading ? null : _stylize,
              child: loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('STYLIZE'),
            ),
            const SizedBox(height: 16),
            if (resultBytes != null)
              _resultCard(
                Image.memory(resultBytes!, fit: BoxFit.contain),
                Theme.of(context).colorScheme,
              ),
          ],
        ),
      ),
    );
  }

  Widget _imageCard(File? f, String hint, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: f == null
                ? Center(
                    child: Text(hint, style: const TextStyle(fontSize: 16)),
                  )
                : Image.file(f, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(Widget child, ColorScheme cs) {
    return Card(
      elevation: 8,
      shadowColor: cs.primary.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sonuç',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
          ],
        ),
      ),
    );
  }
}

/* ===================== 2) FOTOĞRAFLAR SAYFASI ===================== */

class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key, required this.content, required this.style});
  final File? content;
  final File? style;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[_slot('Content', content), _slot('Style', style)];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Fotoğraflar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: MediaQuery.of(context).size.width > 720 ? 3 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: tiles,
          ),
        ),
      ),
    );
  }

  Widget _slot(String title, File? f) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: f == null
                  ? const Center(child: Text('Seçilmedi'))
                  : Image.file(f, fit: BoxFit.cover),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(title, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== 3) GEÇMİŞ SAYFASI ===================== */

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.history});
  final List<Uint8List> history;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Geçmiş')),
      body: history.isEmpty
          ? const Center(child: Text('Henüz sonuç yok'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 720
                        ? 3
                        : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: history.length,
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(history[i], fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
    );
  }
}
