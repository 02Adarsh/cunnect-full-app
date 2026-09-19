import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../services/open_url.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// ⭐ v59: in-app document viewer — PDFs render inside the app (no more
/// browser redirect), images show inline, anything else falls back to
/// the external opener. Used by the UMS lecture plan and the print
/// vendor's order file.
class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  /// Optional auth headers for protected backend endpoints.
  final Map<String, String>? headers;

  const PdfViewerScreen({
    super.key,
    required this.url,
    this.title = 'Document',
    this.headers,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfControllerPinch? _pdf;
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Follow redirects manually so auth headers are not silently lost
      // (Cloudinary signed-download URLs redirect once).
      var url = widget.url;
      http.Response? res;
      for (var hop = 0; hop < 5; hop++) {
        final req = http.Request('GET', Uri.parse(url))
          ..followRedirects = false;
        if (widget.headers != null && hop == 0) {
          req.headers.addAll(widget.headers!);
        }
        final streamed =
            await http.Client().send(req).timeout(const Duration(seconds: 60));
        if (streamed.isRedirect || streamed.statusCode == 301 ||
            streamed.statusCode == 302 || streamed.statusCode == 303 ||
            streamed.statusCode == 307) {
          final loc = streamed.headers['location'];
          if (loc == null || loc.isEmpty) break;
          url = Uri.parse(url).resolve(loc).toString();
          continue;
        }
        res = await http.Response.fromStream(streamed);
        break;
      }
      if (res == null || res.statusCode != 200) {
        throw Exception('Server error ${res?.statusCode ?? ''}'.trim());
      }
      final bytes = res.bodyBytes;
      if (bytes.isEmpty) throw Exception('Empty file received.');

      final ctype = (res.headers['content-type'] ?? '').toLowerCase();
      final isPdf = bytes.length > 4 &&
          bytes[0] == 0x25 && bytes[1] == 0x50 &&
          bytes[2] == 0x44 && bytes[3] == 0x46; // %PDF
      final isImage = ctype.startsWith('image/') ||
          _looksLikeImage(bytes);

      if (isPdf) {
        // pdfx opens from a file path — write to the temp dir.
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/cunnect_doc_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await f.writeAsBytes(bytes, flush: true);
        final doc = PdfDocument.openFile(f.path);
        final controller = PdfControllerPinch(document: doc);
        final opened = await doc;
        if (!mounted) return;
        setState(() {
          _pdf = controller;
          _pages = opened.pagesCount;
          _loading = false;
        });
      } else if (isImage) {
        if (!mounted) return;
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
      } else {
        // Not something we can render (e.g. .docx) — external fallback.
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'external';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _looksLikeImage(Uint8List b) {
    if (b.length < 4) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) return true; // PNG
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46) return true; // WEBP
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        actions: [
          if (_pdf != null && _pages > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x1AF10B1D),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0x40F10B1D)),
                  ),
                  child: Text('$_page / $_pages',
                      style: const TextStyle(
                          color: Color(0xFFFFABB2),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          // v60: the external-open arrow icon was removed at the user's
          // request — the fallback screen still offers OPEN EXTERNALLY.
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.red)))
          : _error == 'external'
              ? _fallback(
                  'This file type cannot be previewed in the app.\n'
                  'Open it externally instead.')
              : _error != null
                  ? _fallback('The document could not be loaded.\n'
                      'Check your connection and try again.')
                  : _imageBytes != null
                      ? InteractiveViewer(
                          maxScale: 6,
                          child: Center(child: Image.memory(_imageBytes!)),
                        )
                      : PdfViewPinch(
                          controller: _pdf!,
                          onPageChanged: (p) => setState(() => _page = p),
                          builders:
                              PdfViewPinchBuilders<DefaultBuilderOptions>(
                            options: const DefaultBuilderOptions(),
                            documentLoaderBuilder: (_) => const Center(
                                child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.red))),
                            pageLoaderBuilder: (_) => const Center(
                                child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.red))),
                          ),
                        ),
    );
  }

  Widget _fallback(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined,
                  size: 40, color: Color(0xFF4A4A4A)),
              const SizedBox(height: 14),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  final err = await openExternalUrl(widget.url);
                  if (err != null && mounted) {
                    showCunnectToast(context, err, error: true);
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF9CA4),
                  side: const BorderSide(color: Color(0x8CF10B1D)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                label: const Text('OPEN EXTERNALLY'),
              ),
            ],
          ),
        ),
      );
}
