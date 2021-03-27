#pragma warning(disable : 4458)
#include <Windows.h>
#include <gdiplus.h>

#include <string>
#include <unordered_map>
#include <iostream>

#include "native_pdf_renderer.h"

#pragma comment(lib, "gdiplus.lib")

namespace native_pdf_renderer
{
    int GetEncoderClsid(const WCHAR *format, CLSID *pClsid)
    {
        UINT num = 0;  // number of image encoders
        UINT size = 0; // size of the image encoder array in bytes

        Gdiplus::ImageCodecInfo *pImageCodecInfo = NULL;

        Gdiplus::GetImageEncodersSize(&num, &size);
        if (size == 0)
            return -1; // Failure

        pImageCodecInfo = (Gdiplus::ImageCodecInfo *)(malloc(size));
        if (pImageCodecInfo == NULL)
            return -1; // Failure

        GetImageEncoders(num, size, pImageCodecInfo);

        for (UINT j = 0; j < num; ++j)
        {
            if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0)
            {
                *pClsid = pImageCodecInfo[j].Clsid;
                free(pImageCodecInfo);
                return j; // Success
            }
        }

        free(pImageCodecInfo);
        return -1; // Failure
    }

    std::unordered_map<std::string, std::shared_ptr<Document>> document_repository;
    std::unordered_map<std::string, std::shared_ptr<Page>> page_repository;
    int lastId = 0;

    std::shared_ptr<Document> openDocument(std::vector<uint8_t> data)
    {
        if (document_repository.size() == 0)
        {
            FPDF_InitLibraryWithConfig(nullptr);
        }

        lastId++;
        std::string strId = std::to_string(lastId);

        std::shared_ptr<Document> doc = std::make_shared<Document>(data, strId);
        document_repository[strId] = doc;

        return doc;
    }

    std::shared_ptr<Document> openDocument(std::string name)
    {
        if (document_repository.size() == 0)
        {
            FPDF_InitLibraryWithConfig(nullptr);
        }

        lastId++;
        std::string strId = std::to_string(lastId);

        std::shared_ptr<Document> doc = std::make_shared<Document>(name, strId);
        document_repository[strId] = doc;

        return doc;
    }

    void closeDocument(std::string id)
    {
        document_repository.erase(id);

        if (document_repository.size() == 0)
        {
            FPDF_DestroyLibrary();
        }
    }

    std::shared_ptr<Page> openPage(std::string docId, int index)
    {
        lastId++;
        std::string strId = std::to_string(lastId);

        std::shared_ptr<Document> doc = document_repository[docId];
        std::shared_ptr<Page> page = std::make_shared<Page>(doc, index, strId);

        page_repository[strId] = page;

        return page;
    }

    void closePage(std::string id)
    {
        page_repository.erase(id);
    }

    PageRender renderPage(std::string id, int width, int height)
    {
        return page_repository[id]->render(width, height);
    }

    //

    Document::Document(std::vector<uint8_t> data, std::string id) : id{id}
    {
        std::cout << "Document created" << std::endl;
        document = FPDF_LoadMemDocument64(data.data(), data.size(), nullptr);
    }

    Document::Document(std::string file, std::string id) : id{id}
    {
        std::cout << "Document created" << std::endl;
        document = FPDF_LoadDocument(file.c_str(), nullptr);
    }

    Document::~Document()
    {
        std::cout << "Document deleted" << std::endl;
        FPDF_CloseDocument(document);
    }

    int Document::getPageCount()
    {
        return FPDF_GetPageCount(document);
    }

    Page::Page(std::shared_ptr<Document> doc, int index, std::string id) : id(id)
    {
        std::cout << "Page created" << std::to_string(index) << std::endl;
        page = FPDF_LoadPage(doc->document, index);
    }

    Page::~Page()
    {
        std::cout << "Page deleted" << std::endl;
        FPDF_ClosePage(page);
    }

    PageDetails Page::getDetails()
    {
        std::cout << "Page got details" << std::endl;
        int width = static_cast<int>(FPDF_GetPageWidthF(page) + 0.5f);
        int height = static_cast<int>(FPDF_GetPageHeightF(page) + 0.5f);

        return PageDetails(width, height);
    }

    PageRender Page::render(int width, int height)
    {
        std::cout << "Page rendered" << std::endl;
        // auto page = FPDF_LoadPage(document, index);
        // if (!page)
        // {
        //     return null;
        // }

        // Create empty bitmap and render page onto it
        auto bitmap = FPDFBitmap_Create(width, height, 0);
        FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff);
        FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, FPDF_ANNOT | FPDF_LCD_TEXT);

        // Convert bitmap into RGBA format
        uint8_t *p = static_cast<uint8_t *>(FPDFBitmap_GetBuffer(bitmap));
        auto stride = FPDFBitmap_GetStride(bitmap);

        // BGRA to RGBA conversion
        for (auto y = 0; y < height; y++)
        {
            auto offset = y * stride;
            for (auto x = 0; x < width; x++)
            {
                auto t = p[offset];
                p[offset] = p[offset + 2];
                p[offset + 2] = t;
                offset += 4;
            }
        }

        // Convert to PNG
        Gdiplus::GdiplusStartupInput gdiplusStartupInput;
        ULONG_PTR gdiplusToken;
        Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

        // Get the CLSID of the PNG encoder.
        CLSID encoderClsid;
        GetEncoderClsid(L"image/png", &encoderClsid);

        // Create gdi+ bitmap from raw image data
        auto winBitmap = new Gdiplus::Bitmap(width, height, stride, PixelFormat32bppRGB, p);

        // Create stream for converted image
        IStream *istream = nullptr;
        CreateStreamOnHGlobal(NULL, TRUE, &istream);

        // Encode image onto stream
        winBitmap->Save(istream, &encoderClsid, NULL);

        // Get raw memory of stream
        HGLOBAL hg = NULL;
        GetHGlobalFromStream(istream, &hg);

        // copy IStream to buffer
        size_t bufsize = GlobalSize(hg);
        std::vector<uint8_t> data;
        data.resize(bufsize);

        //lock & unlock memory
        LPVOID pimage = GlobalLock(hg);
        memcpy(&data[0], pimage, bufsize);
        GlobalUnlock(hg);

        // Close stream
        istream->Release();

        // if (stat == Ok)
        //     printf("Bird.png was saved successfully\n");
        // else
        //     printf("Failure: stat = %d\n", stat);

        // Cleanup gid+
        delete winBitmap;
        Gdiplus::GdiplusShutdown(gdiplusToken);

        FPDFBitmap_Destroy(bitmap);

        std::cout << "Page render complete" << std::endl;
        return PageRender(data, width, height);
    }
}