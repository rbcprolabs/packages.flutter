# PDFx

`Flutter` Render & show PDF documents on **Web**, **MacOs 10.11+**, **Android 5.0+**, **iOS** and **Windows**.

Includes 2 api:
- `renderer` Work with Pdf document, pages, render page to image
- `viewer` Set of flutter widgets & controllers for show renderer result

[![pub package](https://img.shields.io/pub/v/pdfx.svg)](https://pub.dev/packages/pdfx)

## Showcase

| PdfViewPinch              | PdfView                    |
|---------------------------|----------------------------|
|![](https://raw.githubusercontent.com/ScerIO/packages.flutter/main/packages/pdfx/example/media/pinch.gif?raw=true)  | ![](https://raw.githubusercontent.com/ScerIO/packages.flutter/main/packages/pdfx/example/media/simple.gif?raw=true)  |

## Getting Started
In your flutter project add the dependency:
```shell
flutter pub add pdfx
```

For web run tool for automatically add pdfjs library (CDN) in index.html:
```shell
flutter pub run pdfx:install_web
```

For windows run tool automatically add override for pdfium version property in CMakeLists.txt file:
```
flutter pub run pdfx:install_windows
```

## Usage example

```dart
import 'package:pdfx/pdfx.dart';

final pdfPinchController = PdfControllerPinch(
  document: PdfDocument.openAsset('assets/sample.pdf'),
);

// Pdf view with re-render pdf texture on zoom (not loose quality on zoom)
// Not supported on windows
PdfViewPinch(
  controller: pdfPinchController,
);

//-- or --//

final pdfController = PdfController(
  document: PdfDocument.openAsset('assets/sample.pdf'),
);

// Simple Pdf view with one render of page (loose quality on zoom)
PdfView(
  controller: pdfController,
);
```

## Viewer Api

### PdfController & PdfControllerPinch

| Parameter        | Description                                                | Default |
|------------------|------------------------------------------------------------|---------|
| document         | The document to be displayed                               | -       |
| initialPage      | The page to show when first creating the  [PdfView]        | 1       |
| viewportFraction | The fraction of the viewport that each page should occupy. | 1.0     |

### PdfView & PdfViewPinch

| Parameter        	| Description                                                                                                    | PdfViewPinch / PdfView |
|------------------	|----------------------------------------------------------------------------------------------------------------|------------------------|
| controller       	| Pages control. See [page control](#page-control) and  [additional pdf info](#additional-pdf-info)              | + / +                  |
| onPageChanged    	| Called whenever the page in the center of the viewport changes.  See [Document callbacks](#document-callbacks) | + / +                  |
| onDocumentLoaded 	| Called when a document is loaded. See [Document callbacks](#document-callbacks)                                | + / +                  |
| onDocumentError  	| Called when a document loading error. Exception is passed in the attributes                                    | + / +                  |
| builders         	| Set of pdf view builders. See [Custom builders](#custom-builders)                                              | + / +                  |
| scrollDirection  	| Page turning direction                                                                                         | + / +                  |
| reverse  	        | Reverse scroll direction, useful for RTL support                                                               | - / +                  |
| renderer         	| Custom PdfRenderer options.  See [custom renderer options](#custom-renderer-options)                           | - / +                  |
| pageSnapping     	| Set to false for mouse wheel scroll on web                                                                     | - / +                  |
| physics          	| How the widgets should respond to user input                                                                   | - / +                  |
| padding          	| Padding for the every page.                                                                                    | + / -                  |
| minScale          | The minimum document zoom scale.                                                                               | + / -                  |
| maxScale          | The maximum document zoom scale.                                                                               | + / -                  |

### PdfViewBuilders & PdfViewPinchBuilders

| Parameter             	| Description                                                                                       | PdfViewPinchBuilders / PdfViewBuilders |
|-----------------------	|---------------------------------------------------------------------------------------------------|----------------------------------------|
| options               	| Additional options for builder                                                                    | + / +                                  |
| documentLoaderBuilder 	| Widget showing when pdf document loading                                                          | + / +                                  |
| pageLoaderBuilder     	| Widget showing when pdf page loading                                                              | + / +                                  |
| errorBuilder          	| Show document loading error message                                                               | + / +                                  |
| builder               	| Root view builder for animate pdf loading state                                                   | + / +                                  |
| pageBuilder           	| Callback called to render a widget for each page. See [custom page builder](#custom-page-builder) | - / +                                  |

## Additional examples

### Open another document
```dart
pdfController.openDocument(PdfDocument.openAsset('assets/sample.pdf'));
```

### Page control:
```dart
// Jump to specified page
pdfController.jumpTo(3);

// Animate to specified page
_pdfController.animateToPage(3, duration: Duration(milliseconds: 250), curve: Curves.ease);

// Animate to next page
_pdfController.nextPage(duration: Duration(milliseconds: 250), curve: Curves.easeIn);

// Animate to previous page
_pdfController.previousPage(duration: Duration(milliseconds: 250), curve: Curves.easeOut);

// Get document progrees 0.0 - start, 1.0 - end
_pdfController.documentProgress;
```
### Additional pdf info:
```dart
// Actual showed page
pdfController.page;

// Count of all pages in document
pdfController.pagesCount;
```

### Document callbacks
```dart
PdfView(
  controller: pdfController,
  onDocumentLoaded: (document) {},
  onPageChanged: (page) {},
);
```

### Show actual page number & all pages count
```dart
PdfPageNumber(
  controller: _pdfController,
  // When `loadingState != PdfLoadingState.success`  `pagesCount` equals null_
  builder: (_, state, loadingState, pagesCount) => Container(
    alignment: Alignment.center,
    child: Text(
      '$page/${pagesCount ?? 0}',
      style: const TextStyle(fontSize: 22),
    ),
  ),
)
```

### Custom renderer options
```dart
PdfView(
  controller: pdfController,
  renderer: (PdfPage page) => page.render(
    width: page.width * 2,
    height: page.height * 2,
    format: PdfPageImageFormat.jpeg,
    backgroundColor: '#FFFFFF',
  ),
);
```

### Custom builders
```dart
// Need static methods for builders arguments
class SomeWidget {
  static Widget builder(
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

  static Widget transitionBuilder(Widget child, Animation<double> animation) =>
      FadeTransition(opacity: animation, child: child);

  static PhotoViewGalleryPageOptions pageBuilder(
    BuildContext context,
    Future<PdfPageImage> pageImage,
    int index,
    PdfDocument document,
  ) =>
      PhotoViewGalleryPageOptions(
        imageProvider: PdfPageImageProvider(
          pageImage,
          index,
          document.id,
        ),
        minScale: PhotoViewComputedScale.contained * 1,
        maxScale: PhotoViewComputedScale.contained * 3.0,
        initialScale: PhotoViewComputedScale.contained * 1.0,
        heroAttributes: PhotoViewHeroAttributes(tag: '${document.id}-$index'),
      );
}

PdfViewPinch(
  controller: pdfPinchController,
  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
    options: const DefaultBuilderOptions(
      loaderSwitchDuration: const Duration(seconds: 1),
      transitionBuilder: SomeWidget.transitionBuilder,
    ),
    documentLoaderBuilder: (_) =>
        const Center(child: CircularProgressIndicator()),
    pageLoaderBuilder: (_) =>
        const Center(child: CircularProgressIndicator()),
    errorBuilder: (_, error) => Center(child: Text(error.toString())),
    builder: SomeWidget.builder,
  ),
)

PdfView(
  controller: pdfController,
  builders: PdfViewBuilders<DefaultBuilderOptions>(
    // All from `PdfViewPinch` and:
    pageBuilder: SomeWidget.pageBuilder,
  ),
);
```

## Renderer Api

### PdfDocument

| Parameter  | Description                                                                                | Default |
|------------|--------------------------------------------------------------------------------------------|---------|
| sourceName | Needed for toString method. Contains a method for opening a document (file, data or asset) | -       |
| id         | Document unique id. Generated when opening document.                                       | -       |
| pagesCount | All pages count in document. Starts from 1.                                                | -       |
| isClosed   | Is the document closed                                                                     | -       |

**Local document open:**
```dart
// From assets (Android, Ios, MacOs, Web)
final document = await PdfDocument.openAsset('assets/sample.pdf')

// From file (Android, Ios, MacOs)
final document = await PdfDocument.openFile('path/to/file/on/device')

// From data (Android, Ios, MacOs, Web)
final document = await PdfDocument.openData((FutureOr<Uint8List>) data)
```
**Network document open:**

Install [[network_file]](https://pub.dev/packages/internet_file) package (supports all platforms):
```shell
flutter pub add internet_file
```

And use it
```dart
import 'package:internet_file/internet_file.dart';

PdfDocument.openData(InternetFile.get('https://github.com/ScerIO/packages.flutter/raw/fd0c92ac83ee355255acb306251b1adfeb2f2fd6/packages/native_pdf_renderer/example/assets/sample.pdf'))
```

**Open page:**
```dart
final page = document.getPage(pageNumber); // Starts from 1
```

**Close document:**
```dart
document.close();
```

### PdfPage

| Parameter | Description                                                                         | Default |
|-----------|-------------------------------------------------------------------------------------|---------|
| document  | Parent document                                                                     | Parent  |
| id        | Page unique id. Needed for rendering and closing page. Generated when opening page. | -       |
| width     | Page source width in pixels, int                                                    | -       |
| height    | Page source height in pixels, int                                                   | -       |
| isClosed  | Is the page closed                                                                  | false   |

**Render image:**
```dart
final pageImage = page.render(
  // rendered image width resolution, required
  width: page.width * 2,
  // rendered image height resolution, required
  height: page.height * 2,

  // Rendered image compression format, also can be PNG, WEBP*
  // Optional, default: PdfPageImageFormat.PNG
  // Web not supported
  format: PdfPageImageFormat.JPEG,

  // Image background fill color for JPEG
  // Optional, default '#ffffff'
  // Web not supported
  backgroundColor: '#ffffff',

  // Crop rect in image for render
  // Optional, default null
  // Web not supported
  cropRect: Rect.fromLTRB(left, top, right, bottom),
);
```

### PdfPageImage

| Parameter  | Description                                                                        | Default           |
|------------|------------------------------------------------------------------------------------|-------------------|
| id         | Page unique id. Needed for rendering and closing page. Generated when render page. | -                 |
| pageNumber | Page number. The first page is 1.                                                  | -                 |
| width      | Width of the rendered area in pixels, int                                          | -                 |
| height     | Height of the rendered area in pixels, int                                         | -                 |
| bytes      | Rendered image result, Uint8List                                                   | -                 |
| format     | Rendered image compression format, for web always PNG                              | PdfPageImageFormat.PNG |

**Close page:**
<br>
Before open new page android asks to close the past. <br>
If this is not done, the application may crash with an error
```dart
page.close();
```

\* __PdfPageImageFormat.WEBP support only on android__

## Rendering additional info

### On Web
This plugin uses the [PDF.js](https://mozilla.github.io/pdf.js/)

### On Android
This plugin uses the Android native [PdfRenderer](https://developer.android.com/reference/android/graphics/pdf/PdfRenderer)

### On Ios & MacOs
This plugin uses the iOS & MacOs native [CGPDFPage](https://developer.apple.com/documentation/coregraphics/cgpdfdocument/cgpdfpage)

### On Windows
This plugin uses [PDFium](https://pdfium.googlesource.com/pdfium/+/master/README.md)
