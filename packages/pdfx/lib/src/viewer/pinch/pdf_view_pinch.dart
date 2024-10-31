import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart'
    hide InteractiveViewer, TransformationController;
import 'package:pdfx/src/renderer/interfaces/document.dart';
import 'package:pdfx/src/renderer/interfaces/page.dart';
import 'package:pdfx/src/viewer/base/base_pdf_builders.dart';
import 'package:pdfx/src/viewer/base/base_pdf_controller.dart';
import 'package:pdfx/src/viewer/interactive_viewer.dart';
import 'package:pdfx/src/viewer/wrappers/pdf_texture.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:vector_math/vector_math_64.dart' as math64;

export 'package:pdfx/src/viewer/pdf_page_image_provider.dart';
export 'package:photo_view/photo_view.dart';
export 'package:photo_view/photo_view_gallery.dart';

part 'pdf_controller_pinch.dart';
part 'pdf_view_pinch_builders.dart';

/// Widget for viewing PDF documents with pinch to zoom feature
class PdfViewPinch extends StatefulWidget {
  const PdfViewPinch({
    required this.controller,
    this.onPageChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const PdfViewPinchBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.scrollDirection = Axis.vertical,
    this.padding = 10,
    this.minScale = 1.0,
    this.maxScale = 20.0,
    this.backgroundDecoration = const BoxDecoration(
      color: Color.fromARGB(255, 250, 250, 250),
      boxShadow: [
        BoxShadow(
          color: Color(0x73000000),
          blurRadius: 4,
          offset: Offset(2, 2),
        ),
      ],
    ),
    Key? key,
  }) : super(key: key);

  /// Padding for the every page.
  final double padding;

  /// The minimum document zoom scale.
  final double minScale;

  /// The maximum document zoom scale.
  final double maxScale;

  /// Page management
  final PdfControllerPinch controller;

  /// Called whenever the page in the center of the viewport changes
  final void Function(int page)? onPageChanged;

  /// Called when a document is loaded
  final void Function(PdfDocument document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Object error)? onDocumentError;

  /// Builders
  final PdfViewPinchBuilders builders;

  /// Page turning direction
  final Axis scrollDirection;

  /// Pdf widget page background decoration
  final BoxDecoration backgroundDecoration;

  /// Default page builder
  @override
  State<PdfViewPinch> createState() => _PdfViewPinchState();
}

class _PdfViewPinchState extends State<PdfViewPinch>
    with SingleTickerProviderStateMixin {
  PdfControllerPinch get _controller => widget.controller;
  final List<_PdfPageState> _pages = [];
  final List<_PdfPageState> _pendedPageDisposes = [];
  Exception? _loadingError;
  Size? _lastViewSize;
  Timer? _realSizeUpdateTimer;
  Size? _docSize;
  final Map<int, double> _visiblePages = <int, double>{};

  late AnimationController _animController;
  Animation<Matrix4>? _animGoTo;

  bool _firstControllerAttach = true;
  bool _forceUpdatePagePreviews = true;

  double get _padding => widget.padding;
  double get _minScale => widget.minScale;
  double get _maxScale => widget.maxScale;

  @override
  void initState() {
    super.initState();
    if (UniversalPlatform.isWindows) {
      throw UnimplementedError(
          'PdfViewPinch not supported in Windows, usage PdfView instead');
    }
    _controller._attach(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    widget.controller.loadingState.addListener(() {
      switch (widget.controller.loadingState.value) {
        case PdfLoadingState.loading:
          _pages.clear();
          break;
        case PdfLoadingState.success:
          widget.onDocumentLoaded?.call(widget.controller._document!);
          break;
        case PdfLoadingState.error:
          widget.onDocumentError?.call(_loadingError!);
          break;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller._detach();
    _cancelLastRealSizeUpdate();
    _releasePages();
    _handlePendedPageDisposes();
    _controller.removeListener(_determinePagesToShow);
    _animController.dispose();
    super.dispose();
  }

  void _releasePages() {
    if (_pages.isEmpty) {
      return;
    }
    for (final p in _pages) {
      p.releaseTextures();
    }
    _pendedPageDisposes.addAll(_pages);
    _pages.clear();
  }

  void _handlePendedPageDisposes() {
    for (final p in _pendedPageDisposes) {
      p.releaseTextures();
    }
    _pendedPageDisposes.clear();
  }

  /// Go to the specified location by the matrix.
  Future<void> _goTo({
    Matrix4? destination,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    try {
      if (destination == null) {
        return;
      } // do nothing
      _animGoTo?.removeListener(_updateControllerMatrix);
      _animController.reset();
      _animGoTo = Matrix4Tween(begin: _controller.value, end: destination)
          .animate(_animController);
      _animGoTo!.addListener(_updateControllerMatrix);
      await _animController
          .animateTo(1.0, duration: duration, curve: curve)
          .orCancel;
    } on TickerCanceled {
      // expected
    }
  }

  void _updateControllerMatrix() {
    _controller.value = _animGoTo!.value;
  }

  void _reLayout(Size? viewSize) {
    if (_pages.isEmpty) {
      return;
    }
    // if (widget.params?.layoutPages == null) {
    _reLayoutDefault(viewSize!);
    // } else {
    // final contentSize =
    //     Size(viewSize!.width - _padding * 2, viewSize.height - _padding * 2);
    // final rects = widget.params!.layoutPages!(
    //     contentSize, _pages!.map((p) => p.pageSize).toList());
    // var allRect = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
    // for (int i = 0; i < _pages!.length; i++) {
    //   final rect = rects[i].translate(_padding, _padding);
    //   _pages![i].rect = rect;
    //   allRect = allRect.expandToInclude(rect.inflate(_padding));
    // }
    // _docSize = allRect.size;
    // }
    _lastViewSize = viewSize;

    if (_firstControllerAttach) {
      _firstControllerAttach = false;

      Future.delayed(Duration.zero, () {
        // NOTE: controller should be associated
        // after first layout calculation finished.
        _controller
          ..addListener(_determinePagesToShow)
          .._setViewerState(this);
        // widget.params?.onViewerControllerInitialized?.call(_controller);

        if (mounted) {
          final initialPage = _controller.initialPage;
          if (initialPage != 1) {
            final m =
                _controller.calculatePageFitMatrix(pageNumber: initialPage);
            if (m != null) {
              _controller.value = m;
            }
          }
          _forceUpdatePagePreviews = true;
          _determinePagesToShow();
        }
      });
      return;
    }

    _determinePagesToShow();
  }

  /// Default page layout logic that layouts pages vertically.
  void _reLayoutDefault(Size viewSize) {
    final maxWidth = _pages.fold<double>(
        0.0, (maxWidth, page) => max(maxWidth, page.pageSize.width));
    final ratio = (viewSize.width - _padding * 2) / maxWidth;
    if (widget.scrollDirection == Axis.horizontal) {
      var left = _padding;
      for (int i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        final w = page.pageSize.width * ratio;
        final h = page.pageSize.height * ratio;
        page.rect = Rect.fromLTWH(left, _padding, w, h);
        left += w + _padding;
      }
      _docSize = Size(left, viewSize.height);
    } else {
      var top = _padding;
      for (int i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        final w = page.pageSize.width * ratio;
        final h = page.pageSize.height * ratio;
        page.rect = Rect.fromLTWH(_padding, top, w, h);
        top += h + _padding;
      }
      _docSize = Size(viewSize.width, top);
    }
  }

  /// Not to purge loaded page previews if they're "near"
  ///  from the current exposed view
  static const _extraBufferAroundView = 400.0;

  void _determinePagesToShow() {
    if (_lastViewSize == null || _pages.isEmpty) {
      return;
    }

    Matrix4? m;
    final pendingInitialPage = _controller.pendingInitialPage;
    bool shouldNotifyPageChanged = false;
    if (pendingInitialPage != null) {
      m = _controller.calculatePageFitMatrix(pageNumber: pendingInitialPage);
      shouldNotifyPageChanged = true;
    }
    m ??= _controller.value;

    final r = m.row0[0];
    final exposed = Rect.fromLTWH(
        -m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height);

    if (_lastViewSize?.height != null) {
      final rawDocumentProgress =
          ((exposed.bottom / r - _lastViewSize!.height) /
              (_docSize!.height - _lastViewSize!.height));
      const precisionFactor = 10000;
      _controller._documentProgress =
          ((rawDocumentProgress * precisionFactor).round() / precisionFactor)
              .clamp(0.0, 1.0);
    }

    var pagesToUpdate = 0;
    var changeCount = 0;
    _visiblePages.clear();
    for (final page in _pages) {
      if (page.rect == null) {
        page.isVisibleInsideView = false;
        continue;
      }
      final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
          page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      final isVisible = !part.isEmpty;
      if (isVisible) {
        _visiblePages[page.pageNumber] = part.width * part.height;
      }
      if (page.isVisibleInsideView != isVisible) {
        page.isVisibleInsideView = isVisible;
        changeCount++;
        if (isVisible) {
          pagesToUpdate++; // the page gets inside the view
        }
      }
    }

    _cancelLastRealSizeUpdate();

    if (changeCount > 0) {
      _needReLayout();
    }
    if (pagesToUpdate > 0 || _forceUpdatePagePreviews) {
      _needPagePreviewGeneration();
    } else {
      _needRealSizeOverlayUpdate();
    }

    if (shouldNotifyPageChanged && pendingInitialPage != null) {
      widget.onPageChanged?.call(pendingInitialPage);
      _controller.pageListenable.value = pendingInitialPage;
    }
  }

  void _needReLayout() {
    Future.delayed(Duration.zero, () => setState(() {}));
  }

  void _needPagePreviewGeneration() {
    Future.delayed(Duration.zero, _updatePageState);
  }

  Future<void> _updatePageState() async {
    if (_pages.isEmpty) {
      return;
    }
    _forceUpdatePagePreviews = false;
    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (page.rect == null) {
        continue;
      }
      final m = _controller.value;
      final r = m.row0[0];
      final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3],
              _lastViewSize!.width, _lastViewSize!.height)
          .inflate(_extraBufferAroundView);

      final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
          page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) {
        continue;
      }

      if (page.status == _PdfPageLoadingStatus.notInitialized) {
        page
          ..status = _PdfPageLoadingStatus.initializing
          ..pdfPage = await _controller._document!.getPage(
            page.pageNumber,
            autoCloseAndroid: true,
          );
        final prevPageSize = page.pageSize;
        page
          ..pageSize = Size(page.pdfPage.width, page.pdfPage.height)
          ..status = _PdfPageLoadingStatus.initialized;
        if (prevPageSize != page.pageSize && mounted) {
          _reLayout(_lastViewSize);
          return;
        }
      }
      if (page.status == _PdfPageLoadingStatus.initialized) {
        page
          ..status = _PdfPageLoadingStatus.pageLoading
          ..preview = await page.pdfPage.createTexture();
        final w = page.pdfPage.width; // * 2;
        final h = page.pdfPage.height; // * 2

        await page.preview!.updateRect(
          documentId: _controller._document!.id,
          width: w.toInt(),
          height: h.toInt(),
          textureWidth: w.toInt(),
          textureHeight: h.toInt(),
          fullWidth: w,
          fullHeight: h,
          allowAntiAliasing: true,
          backgroundColor: '#ffffff',
        );

        page
          ..status = _PdfPageLoadingStatus.pageLoaded
          ..updatePreview();
      }
    }

    _needRealSizeOverlayUpdate();
  }

  Future<void> _updateRealSizeOverlay() async {
    if (_pages.isEmpty) {
      return;
    }

    const fullPurgeDistThreshold = 33;
    const partialRemovalDistThreshold = 8;

    final dpr = View.of(context).devicePixelRatio;
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(
        -m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height);
    final distBase = max(_lastViewSize!.height, _lastViewSize!.width);
    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (page.rect == null ||
          page.status != _PdfPageLoadingStatus.pageLoaded) {
        continue;
      }
      final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
          page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) {
        final dist = (exposed.center - pageRectZoomed.center).distance;
        if (dist > distBase * fullPurgeDistThreshold) {
          page.releaseTextures();
        } else if (dist > distBase * partialRemovalDistThreshold) {
          page.releaseRealSize();
        }
        continue;
      }
      final fw = pageRectZoomed.width * dpr;
      final fh = pageRectZoomed.height * dpr;
      if (page.preview?.hasUpdatedTexture == true &&
          fw <= page.preview!.textureWidth! &&
          fh <= page.preview!.textureHeight!) {
        // no real-size overlay needed; use preview
        page.realSizeOverlayRect = null;
      } else {
        // render real-size overlay
        final offset = part.topLeft - pageRectZoomed.topLeft;
        page
          ..realSizeOverlayRect = Rect.fromLTWH(
            offset.dx / r,
            offset.dy / r,
            part.width / r,
            part.height / r,
          )
          ..realSize ??= await page.pdfPage.createTexture();
        final w = (part.width * dpr).toInt();
        final h = (part.height * dpr).toInt();
        await page.realSize!.updateRect(
          documentId: _controller._document!.id,
          width: w,
          height: h,
          sourceX: (offset.dx * dpr).toInt(),
          sourceY: (offset.dy * dpr).toInt(),
          textureWidth: w,
          textureHeight: h,
          fullWidth: fw,
          fullHeight: fh,
          allowAntiAliasing: true,
          backgroundColor: '#ffffff',
        );
        page._updateRealSizeOverlay();
      }
    }
  }

  void _cancelLastRealSizeUpdate() {
    if (_realSizeUpdateTimer != null) {
      _realSizeUpdateTimer!.cancel();
      _realSizeUpdateTimer = null;
    }
  }

  final _realSizeOverlayUpdateBufferDuration =
      const Duration(milliseconds: 100);

  void _needRealSizeOverlayUpdate() {
    _cancelLastRealSizeUpdate();
    // Using Timer as cancellable version of [Future.delayed]
    _realSizeUpdateTimer =
        Timer(_realSizeOverlayUpdateBufferDuration, _updateRealSizeOverlay);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      widget.controller._document,
      _loadingError,
    );
  }

  static Widget _builder(
    BuildContext context,
    PdfViewPinchBuilders builders,
    PdfLoadingState state,
    WidgetBuilder loadedBuilder,
    PdfDocument? document,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case PdfLoadingState.loading:
          return KeyedSubtree(
            key: const Key('pdfx.root.loading'),
            child: builders.documentLoaderBuilder?.call(context) ??
                const SizedBox(),
          );
        case PdfLoadingState.error:
          return KeyedSubtree(
            key: const Key('pdfx.root.error'),
            child: builders.errorBuilder?.call(context, loadingError!) ??
                Center(child: Text(loadingError.toString())),
          );
        case PdfLoadingState.success:
          return KeyedSubtree(
            key: Key('pdfx.root.success.${document!.id}'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder =
        builders as PdfViewPinchBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  Widget _buildLoaded(BuildContext context) {
    Future.microtask(_handlePendedPageDisposes);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        _reLayout(viewSize);
        final docSize = _docSize ?? const Size(10, 10); // dummy size
        return InteractiveViewer(
          transformationController: _controller,
          scrollControls: InteractiveViewerScrollControls.scrollPans,
          constrained: false,
          alignPanAxis: false,
          boundaryMargin: _minScale < 1
              ? const EdgeInsets.all(double.infinity)
              : EdgeInsets.zero,
          minScale: _minScale,
          maxScale: _maxScale,
          panEnabled: true,
          scaleEnabled: true,
          child: SafeArea(
            child: Stack(
              children: <Widget>[
                SizedBox(width: docSize.width, height: docSize.height),
                ...iterateLaidOutPages(viewSize)
              ],
            ),
          ),
        );
      },
    );
  }

  Iterable<Widget> iterateLaidOutPages(Size viewSize) sync* {
    if (!_firstControllerAttach && _pages.isNotEmpty) {
      final m = _controller.value;
      final r = m.row0[0];
      final exposed =
          Rect.fromLTWH(-m.row0[3], -m.row1[3], viewSize.width, viewSize.height)
              .inflate(_padding);

      for (var i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        if (page.rect == null) {
          continue;
        }
        final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
            page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
        final part = pageRectZoomed.intersect(exposed);
        page.isVisibleInsideView = !part.isEmpty;
        if (!page.isVisibleInsideView) {
          continue;
        }

        yield Positioned(
          left: page.rect!.left,
          top: page.rect!.top,
          width: page.rect!.width,
          height: page.rect!.height,
          child: Container(
            width: page.rect!.width,
            height: page.rect!.height,
            decoration: widget.backgroundDecoration,
            child: Stack(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: page._previewNotifier,
                  builder: (context, value, child) => page.preview != null
                      ? Positioned.fill(
                          child: PdfTexture(textureId: page.preview!.id),
                        )
                      : Container(),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: page._realSizeNotifier,
                  builder: (context, value, child) =>
                      page.realSizeOverlayRect != null && page.realSize != null
                          ? Positioned(
                              left: page.realSizeOverlayRect!.left,
                              top: page.realSizeOverlayRect!.top,
                              width: page.realSizeOverlayRect!.width,
                              height: page.realSizeOverlayRect!.height,
                              child: PdfTexture(textureId: page.realSize!.id),
                            )
                          : Container(),
                ),
              ],
            ),
          ),
        );
      }
    }
  }
}
