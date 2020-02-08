import 'package:epub/epub.dart';
import 'package:html/dom.dart';

class EpubCfiGenerator {
  String generateCompleteCFI(String packageDocumentCFIComponent,
          String contentDocumentCFIComponent) =>
      'epubcfi(' +
      packageDocumentCFIComponent +
      contentDocumentCFIComponent +
      ')';

  String generatePackageDocumentCFIComponent(
      String idRef, EpubPackage packageDocument) {
    // this.validatePackageDocument(packageDocument);

    final pos = getIdRefPosition(idRef, packageDocument);

    // Append an !; this assumes that a CFI content document CFI component
    // will be appended at some point
    return '/6/$pos[$idRef]!';
  }

  String generateElementCFIComponent(Element startElement) {
    // this.validateStartElement(startElement);

    // Call the recursive method to create all the steps up to the head element
    // of the content document (the "html" element)
    final contentDocCFI = createCFIElementSteps(startElement, 'html');

    // Remove the !
    return contentDocCFI.substring(1, contentDocCFI.length);
  }

  String createCFIElementSteps(Element currNode, String topLevelElement) {
    int currNodePosition = 0;
    String elementStep = '';

    // Find position of current node in parent list
    int index = 0;
    currNode.parent.children.forEach((node) {
      if (node == currNode) {
        currNodePosition = index;
      }
      index++;
    });

    // Convert position to the CFI even-integer representation
    final int cfiPosition = (currNodePosition + 1) * 2;

    // Create CFI step with id assertion, if the element has an id
    if (currNode.attributes.containsKey('id')) {
      elementStep =
          '/' + cfiPosition.toString() + '[' + currNode.attributes['id'] + ']';
    } else {
      elementStep = '/' + cfiPosition.toString();
    }

    // If a parent is an html element return the (last) step for this content
    // document, otherwise, continue.
    //   Also need to check if the current node is the top-level element.
    //   This can occur if the start node is also the
    //   top level element.
    final parentNode = currNode.parent;
    if (parentNode.localName == topLevelElement ||
        currNode.localName == topLevelElement) {
      // If the top level node is a type from which an indirection step, add an
      // indirection step character (!)
      // REFACTORING CANDIDATE: It is possible that this should be changed to:
      // if (topLevelElement = 'package') do
      //   not return an indirection character. Every other type of top-level
      //   element may require an indirection
      //   step to navigate to, thus requiring that ! is always prepended.
      if (topLevelElement == 'html') {
        return '!' + elementStep;
      } else {
        return elementStep;
      }
    } else {
      return createCFIElementSteps(parentNode, topLevelElement) + elementStep;
    }
  }

  int getIdRefPosition(String idRef, EpubPackage packageDocument) {
    final items = packageDocument.Spine.Items;
    int index = 0;

    for (var i = 0; i < items.length; i++) {
      if (idRef == items[i].IdRef) {
        index = i;
        break;
      }
    }

    return (index + 1) * 2;
  }
}
